local util = require("clingy.util")
local adapter = require("clingy.adapter")
local providers = require("clingy.completion.providers")

local M = {}

---Marks the root node of the CLI application.
function M.root(node)
  if type(node) ~= "table" or node._tag ~= "node" then
    error("c.root must be passed a c.node(...)")
  end
  return {
    _tag = "root",
    node = node,
  }
end

---Defines a command node in the CLI router tree.
---@param children_and_decls table Array of declarations + string-keyed child nodes.
---@param metadata table? Optional metadata: { description = "...", aliases = { ... }, hidden = false }
function M.node(children_and_decls, metadata)
  children_and_decls = children_and_decls or {}
  metadata = metadata or {}

  local declarations = {}
  local children = {}

  for k, v in pairs(children_and_decls) do
    if type(k) == "number" then
      declarations[k] = v
    elseif type(k) == "string" then
      if type(v) ~= "table" or (v._tag ~= "node" and v._tag ~= "root") then
        error(string.format("Child '%s' must be a c.node(...)", k))
      end
      if v._tag == "root" then
        children[k] = v.node
      else
        children[k] = v
      end
    else
      error(string.format("Invalid key type in c.node: %s", type(k)))
    end
  end

  return {
    _tag = "node",
    declarations = declarations,
    children = children,
    metadata = metadata,
  }
end

---Reusable grammar fragment for composition.
---@param declarations table Array of declarations
function M.group(declarations)
  if type(declarations) ~= "table" then
    error("c.group must be passed a table of declarations")
  end
  return {
    _tag = "group",
    declarations = declarations,
  }
end

---Explicit downward inheritance wrapper.
---@param ... any Declarations, groups, or parser modes to inherit downward
function M.inherit(...)
  local items = { ... }
  if #items == 1 and type(items[1]) == "table" and items[1]._tag == nil and util.is_array(items[1]) then
    items = items[1]
  end
  return {
    _tag = "inherit",
    items = items,
  }
end

---Declares a positional argument.
---Default occurrence: 1..1
---Default values: 1..1
---Default aggregate: "scalar"
function M.arg(name, schema)
  if type(name) ~= "string" or name == "" then
    error("c.arg requires a non-empty string name")
  end
  return {
    _tag = "declaration",
    kind = "arg",
    name = name,
    result_key = name,
    schema = schema,
    occurrence = { min = 1, max = 1 },
    values = { min = 1, max = 1 },
    aggregate = "scalar",
  }
end

---Declares a named option with a value.
---Default occurrence: 0..1
---Default values: 1..1
---Default aggregate: "scalar"
function M.option(...)
  local args = { ... }
  local names = {}
  local schema = nil

  for i, a in ipairs(args) do
    if type(a) == "string" and a:sub(1, 1) == "-" then
      table.insert(names, a)
    else
      schema = a
    end
  end

  if #names == 0 then
    error("c.option requires at least one flag/option name starting with '-'")
  end

  local key = util.derive_key(names)

  return {
    _tag = "declaration",
    kind = "option",
    names = names,
    result_key = key,
    schema = schema,
    occurrence = { min = 0, max = 1 },
    values = { min = 1, max = 1 },
    aggregate = "scalar",
  }
end

---Declares a boolean flag.
---Default occurrence: 0..1
---Default values: 0..0
---Default aggregate: "scalar"
---Absent: false, Present: true
function M.flag(...)
  local args = { ... }
  local names = {}
  local metadata = nil
  for _, a in ipairs(args) do
    if type(a) == "string" and a:sub(1, 1) == "-" then
      table.insert(names, a)
    elseif type(a) == "table" and not a._tag then
      metadata = a
    else
      error(string.format("c.flag names must start with '-', got: %s", tostring(a)))
    end
  end

  if #names == 0 then
    error("c.flag requires at least one flag name starting with '-'")
  end

  local key = util.derive_key(names)

  return {
    _tag = "declaration",
    kind = "flag",
    names = names,
    result_key = key,
    occurrence = { min = 0, max = 1 },
    values = { min = 0, max = 0 },
    aggregate = "scalar",
    default = false,
    metadata = metadata or {},
  }
end

---Cardinality modifier: sets occurrence.min = 0. Preserves occurrence.max.
function M.optional(decl)
  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.optional must wrap a declaration (c.arg, c.option, c.flag)")
  end
  local d = util.deep_copy(decl)
  d._inner = decl
  d.occurrence = d.occurrence or { min = 1, max = 1 }
  d.occurrence.min = 0
  return d
end

---Cardinality modifier: sets occurrence.min = 1. Preserves occurrence.max.
function M.required(decl)
  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.required must wrap a declaration (c.arg, c.option, c.flag)")
  end
  local d = util.deep_copy(decl)
  d._inner = decl
  d.occurrence = d.occurrence or { min = 0, max = 1 }
  d.occurrence.min = 1
  return d
end

---Cardinality modifier: sets occurrence.max = nil (unbounded), aggregate = "array". Preserves occurrence.min.
function M.repeated(decl)
  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.repeated must wrap a declaration (c.arg, c.option, c.flag)")
  end
  local d = util.deep_copy(decl)
  d._inner = decl
  d.occurrence = d.occurrence or { min = 1, max = 1 }
  d.occurrence.max = nil
  if d.kind ~= "flag" then
    d.aggregate = "array"
  end
  return d
end

---Parser mode: interspersed (default). Visible options/flags may appear between positionals.
function M.interspersed()
  return {
    _tag = "parser_mode",
    mode = "interspersed",
  }
end

---Parser mode: leading. Options/flags must precede positionals in segment.
function M.leading()
  return {
    _tag = "parser_mode",
    mode = "leading",
  }
end

---Parser mode: ordered. Declarations must be matched in declared order.
function M.ordered()
  return {
    _tag = "parser_mode",
    mode = "ordered",
  }
end

---Parser capability: short flag clustering (e.g. -xfv -> -x -f -v).
function M.short_clusters()
  return {
    _tag = "short_clusters",
  }
end

---Declares a passthrough capture key for tokens following '--'.
function M.passthrough(key)
  return {
    _tag = "passthrough",
    key = key or "passthrough",
  }
end

---Declares the execution handler for a node.
function M.run(fn)
  if type(fn) ~= "function" then
    error("c.run must be passed a function handler")
  end
  return {
    _tag = "run",
    handler = fn,
  }
end

---Declares signal handlers for a node.
function M.signals(handlers)
  if type(handlers) ~= "table" then
    error("c.signals must be passed a table of signal handlers")
  end
  return {
    _tag = "signals",
    handlers = handlers,
  }
end

M.signal = {
  shutdown = function(opts)
    return { action = "shutdown", opts = opts }
  end,
}

---Declares a lifecycle stage extension.
function M.stage(stage_def)
  if type(stage_def) ~= "table" or not stage_def.id then
    error("c.stage requires a table with an 'id' field")
  end
  return {
    _tag = "stage",
    stage = stage_def,
  }
end

---Attaches a completion provider to a declaration (c.arg or c.option).
---Supports c.complete(provider, decl) and c.complete(decl, provider).
---@param a table Provider or Declaration
---@param b table Provider or Declaration
---@return table Declaration with completion metadata attached
function M.complete(a, b)
  local provider = a
  local decl = b
  if type(a) == "table" and a._tag == "declaration" then
    decl = a
    provider = b
  end

  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.complete must wrap a declaration (c.arg, c.option)")
  end

  if type(provider) ~= "table" or provider._tag ~= "completion_provider" then
    error("c.complete requires a valid completion provider (c.values, c.path, c.file, c.directory, c.dynamic, c.none)")
  end

  local d = util.deep_copy(decl)
  d._inner = decl
  d.completion = {
    origin = provider.kind == "none" and "none" or "explicit",
    provider = provider,
  }
  return d
end

-- Completion provider constructors
M.values = providers.values
M.path = providers.path
M.file = providers.file
M.directory = providers.directory
M.dynamic = providers.dynamic
M.none = providers.none

---Registers a schema adapter.
M.schema_adapter = adapter.register

return M
