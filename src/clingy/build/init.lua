-- Builds a CLI ahead of time. The declaration is compiled once, and the
-- command graph is written as a Lua data module in the public
-- `clingy.built.v1` format (docs/BUILT_FORMAT.md), next to a typed `args`
-- module. `clingy.runtime` runs the result without the DSL, the compiler,
-- help, completion, or schema reflection.
--
-- Functions in the graph (handlers, signal handlers, stages, dynamic
-- completion) must be exports of modules the declaration requires; they are
-- written as `require("module").export`. Schemas are referenced the same way,
-- or recreated when they are inline Valua schemas of a supported shape.

local compiler = require("clingy.compiler")
local router_compiler = require("clingy.router")
local adapter = require("clingy.adapter")
local serialize = require("clingy.build.serialize")
local valua = require("clingy.build.valua")
local args = require("clingy.build.args")

local M = {}

M.FORMAT = "clingy.built.v1"

local NOT_REFERENCES = {
  _G = true, coroutine = true, debug = true, io = true, math = true, os = true, package = true,
  string = true, table = true, utf8 = true, bit = true, bit32 = true, jit = true, ffi = true,
}

local function excluded(name, declaration)
  return name == declaration or NOT_REFERENCES[name] or name:match("^jit%.") or name:match("^table%.")
    or name == "clingy" or name:match("^clingy%.") or name == "valua" or name:match("^valua%.")
end

-- Maps every function or table exported by a loaded module to the
-- expression that loads it. When several modules export the same value, the
-- first module name in sort order wins, so output doesn't depend on load order.
local function index_references(declaration, only)
  local names = {}
  if only then
    for _, name in ipairs(only) do names[#names + 1] = name end
  else
    for name in pairs(package.loaded) do
      if type(name) == "string" and not excluded(name, declaration) then names[#names + 1] = name end
    end
  end
  table.sort(names)
  local refs = {}
  for _, name in ipairs(names) do
    local exported = package.loaded[name]
    if exported == nil and only then exported = require(name) end
    local module_expr = ("require(%q)"):format(name)
    if type(exported) == "function" and refs[exported] == nil then
      refs[exported] = module_expr
    elseif type(exported) == "table" then
      for _, key in ipairs(serialize.sorted_keys(exported)) do
        local value = exported[key]
        local tv = type(value)
        if (tv == "function" or tv == "table") and refs[value] == nil and type(key) == "string" then
          refs[value] = module_expr .. (serialize.is_identifier(key) and ("." .. key) or ("[%q]"):format(key))
        end
      end
    end
  end
  return refs
end

local function module_path(module)
  return (module:gsub("%.", "/")) .. ".lua"
end

local function is_schema(v)
  return type(v) == "table" and type(v["~standard"]) == "table"
end

local function is_provider(v)
  return type(v) == "table" and v._tag == "completion_provider"
end

local function data(v)
  local _, expr = serialize.write(v, { expression = function() return nil end })
  return expr
end

-- Completion providers hold their own closures; rebuild them from kind and data.
local function provider_expression(provider, refs, path)
  local kind = provider.kind
  local call
  if kind == "values" then
    call = "values(" .. data(provider.candidates or {}) .. ")"
  elseif kind == "file" then
    call = "file(" .. data(provider.opts or {}) .. ")"
  elseif kind == "path" or kind == "directory" or kind == "none" then
    call = kind .. "()"
  elseif kind == "dynamic" then
    local fn = refs[provider.fn]
    if not fn then
      error(("dynamic completion at %s uses a function that is not an export of a module the declaration requires"):format(path), 0)
    end
    call = "dynamic(" .. fn .. ")"
  else
    error(("completion provider of kind %s at %s cannot be built"):format(tostring(kind), path), 0)
  end
  return 'require("clingy.completion.providers").' .. call
end

---Builds a CLI declaration.
---@param opts { declaration: string, module: string, args_module?: string|false, runtime_modules?: string[] }
--- - `declaration`: module returning the `c.create` config (or a created app).
--- - `module`: name of the generated built module, e.g. "greet.built".
--- - `args_module`: name of the typed args module (default `<module>.args`), or false for none.
--- - `runtime_modules`: if given, the only modules whose exports may be referenced.
---@return { files: table<string, string>, modules: table<string, string> }
function M.build(opts)
  assert(type(opts) == "table", "clingy.build: options table required")
  assert(type(opts.declaration) == "string", "clingy.build: `declaration` (a module name) is required")
  assert(type(opts.module) == "string", "clingy.build: `module` (the generated module name) is required")

  -- Handlers may require the args module this build generates. On a first
  -- build it doesn't exist yet, so stand in a table whose fields are their own
  -- names, which is what the generated values are.
  local args_module = opts.args_module ~= false and (opts.args_module or (opts.module .. ".args")) or nil
  local stand_in = false
  if args_module and package.loaded[args_module] == nil then
    local found = false
    for _, searcher in ipairs(package.searchers or package.loaders) do
      if type(searcher(args_module)) == "function" then found = true; break end
    end
    if not found then
      stand_in = true
      package.loaded[args_module] = setmetatable({}, { __index = function(commands, command)
        local keys = setmetatable({}, { __index = function(_, key) return key end })
        rawset(commands, command, keys)
        return keys
      end })
    end
  end

  local loaded, config = pcall(require, opts.declaration)
  if stand_in then package.loaded[args_module] = nil end
  if not loaded then error(config, 0) end
  if type(config) == "table" and type(config._config) == "table" then config = config._config end
  local graph = compiler.normalize(config)
  compiler.validate_graph(graph)

  local refs = index_references(opts.declaration, opts.runtime_modules)
  local schemas, schema_index, schema_exprs = {}, {}, {}

  local provider_index, provider_exprs = {}, {}
  local function expression(value, path)
    if is_provider(value) and not refs[value] then
      local index = provider_index[value]
      if not index then
        index = #provider_exprs + 1
        provider_index[value] = index
        provider_exprs[index] = provider_expression(value, refs, path)
      end
      return "P[" .. index .. "]"
    end
    if is_schema(value) then
      local index = schema_index[value]
      if not index then
        local expr = refs[value]
        if not expr and value["~standard"].vendor == "valua" then expr = valua.recreate(value) end
        if not expr then
          error(("schema at %s is not an export of a module the declaration requires, and is not an inline Valua schema clingy.build can recreate; move it into a module and export it"):format(path), 0)
        end
        index = #schema_exprs + 1
        schema_index[value] = index
        schema_exprs[index] = expr
        schemas[index] = value
      end
      return "S[" .. index .. "]"
    end
    return refs[value]
  end

  -- decl_map is keyed by declaration tables, which only exist with c.create.
  -- Built handlers use the generated args module instead.
  local function skip(key, parent)
    return key == "decl_map" and parent.declaration_order ~= nil
  end

  local ok, prelude, graph_expr = pcall(serialize.write, graph, { expression = expression, skip = skip })
  if not ok then
    local message = tostring(prelude)
    if message:find("is not data") then
      message = message .. ". Functions must be exports of a module the declaration requires (for example `c.run(handlers.greet)` with `handlers = require(\"app.handlers\")`); inline functions only work with c.create"
    end
    error("clingy.build: " .. message, 0)
  end

  -- Every schema gets its inspection precomputed, so the runtime never reflects.
  local infos = {}
  for i, schema in ipairs(schemas) do infos[i] = adapter.inspect_schema(schema) end
  local info_prelude, infos_expr = serialize.write(infos, { expression = function() return nil end, shared = "I" })

  local lines = {
    "-- @generated by clingy.build from " .. opts.declaration .. "; do not edit.",
    "-- Format " .. M.FORMAT .. ": see docs/BUILT_FORMAT.md in Clingy.",
    "local S = {",
  }
  for i, expr in ipairs(schema_exprs) do lines[#lines + 1] = "  " .. expr .. ", -- S[" .. i .. "]" end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = "local P = {"
  for i, expr in ipairs(provider_exprs) do lines[#lines + 1] = "  " .. expr .. ", -- P[" .. i .. "]" end
  lines[#lines + 1] = "}"
  if prelude ~= "" then lines[#lines + 1] = prelude end
  lines[#lines + 1] = "local graph = " .. graph_expr
  if info_prelude ~= "" then lines[#lines + 1] = info_prelude end
  lines[#lines + 1] = "local infos = " .. infos_expr
  lines[#lines + 1] = "local schemas = {}"
  lines[#lines + 1] = "for i = 1, #S do schemas[i] = { schema = S[i], info = infos[i] } end"
  lines[#lines + 1] = "return {"
  lines[#lines + 1] = ("  format = %q,"):format(M.FORMAT)
  lines[#lines + 1] = ("  source = %q,"):format(opts.declaration)
  lines[#lines + 1] = "  graph = graph,"
  lines[#lines + 1] = "  schemas = schemas,"
  lines[#lines + 1] = "}"

  local files, modules = {}, {}
  local built_source = table.concat(lines, "\n") .. "\n"
  files[module_path(opts.module)] = built_source
  modules[opts.module] = built_source

  if args_module then
    local args_source = args.generate(router_compiler.compile(graph), args_module)
    files[module_path(args_module)] = args_source
    modules[args_module] = args_source
  end
  return { files = files, modules = modules }
end

---Builds and writes the generated files under `dir` (default ".").
---Directories must already exist.
---@return { files: table<string, string>, modules: table<string, string> }
function M.write(opts, dir)
  local result = M.build(opts)
  for _, path in ipairs(serialize.sorted_keys(result.files)) do
    local target = (dir or ".") .. "/" .. path
    local f, err = io.open(target, "w")
    if not f then error("clingy.build: cannot write " .. target .. ": " .. tostring(err), 0) end
    f:write(result.files[path])
    f:close()
  end
  return result
end

return M
