local util = require("clingy.util")
local adapter = require("clingy.adapter")
local providers = require("clingy.completion.providers")

local M = {}

-- Form atoms describe a value grammar over argv words and offsets.  They are
-- deliberately separate from declarations: an arg or option chooses where a
-- form starts, while these atoms describe what it consumes.
function M.sequence(parts)
  if type(parts) ~= "table" or not util.is_array(parts) or #parts == 0 then
    error("c.sequence requires a non-empty array of form atoms")
  end
  return { _tag = "form_sequence", parts = parts }
end

function M.choice(parts)
  if type(parts) ~= "table" or not util.is_array(parts) or #parts == 0 then
    error("c.choice requires a non-empty array of form atoms")
  end
  return { _tag = "form_choice", parts = parts }
end

function M.next_token()
  return { _tag = "form_next_token" }
end

function M.optional(part)
  if type(part) == "table" and part._tag and part._tag:match("^form_") then
    return { _tag = "form_optional", part = part }
  end
  -- Legacy cardinality is intentionally no longer supported.
  error("c.optional is a form atom; use occurs = { min = 0, max = 1 } on declarations")
end

local function nonblank_string(value, subject)
  if type(value) ~= "string" or value:match("^%s*$") then
    error(subject .. " must be a string containing non-whitespace characters")
  end
  return value
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
      if type(v) ~= "table" or v._tag ~= "node" then
        error(string.format("Child '%s' must be a c.node(...)", k))
      end
      children[k] = v
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
function M.arg(opts)
  if type(opts) ~= "table" or opts.key == nil then
    error("c.arg requires { key = ..., schema = ... }")
  end
  local name = nonblank_string(opts.key, "c.arg key")
  local occurs = opts.occurs or { min = 1, max = 1 }
  if occurs.max == "many" then occurs = { min = occurs.min or 0, max = nil } end
  return {
    _tag = "declaration",
    kind = "arg",
    name = name,
    result_key = name,
    schema = opts.schema,
    form = opts.form,
    completion = opts.complete,
    occurrence = occurs,
    aggregate = opts.occurs and (opts.occurs.max == "many" or (type(opts.occurs.max) == "number" and opts.occurs.max > 1)) and "array" or "scalar",
    values = { min = 1, max = 1 },
  }
end

function M.capture(opts)
  if type(opts) ~= "table" or opts.key == nil then
    error("c.capture requires { key = ..., schema = ... }")
  end
  nonblank_string(opts.key, "c.capture key")
  return { _tag = "form_capture", key = opts.key, schema = opts.schema, complete = opts.complete }
end

function M.literal(opts)
  if type(opts) ~= "table" or opts.text == nil then
    error("c.literal requires { text = ... }")
  end
  return { _tag = "form_literal", text = nonblank_string(opts.text, "c.literal text") }
end

local function validate_aliases(kind, names)
  if #names == 0 then
    error(string.format("c.%s requires at least one flag/option alias starting with '-'", kind))
  end

  for _, name in ipairs(names) do
    if type(name) ~= "string" or name:sub(1, 1) ~= "-" or name == "-" or name == "--" then
      error(string.format("c.%s alias '%s' is not a usable option or flag spelling", kind, name))
    end
  end
end

---Declares a named option with a value.
---Default occurrence: 0..1
---Default values: 1..1
---Default aggregate: "scalar"
function M.option(opts)
  if type(opts) ~= "table" or opts.key == nil then
    error("c.option requires { key = ..., aliases = { ... }, value = { schema = ... } }")
  end
  if not util.is_array(opts.aliases or {}) or #opts.aliases == 0 then
    error("c.option aliases must be a non-empty array")
  end
  validate_aliases("option", opts.aliases)
  nonblank_string(opts.key, "c.option key")
  local value = opts.value or { schema = opts.schema }
  local occurs = opts.occurs or { min = 0, max = 1 }
  if occurs.max == "many" then occurs = { min = occurs.min or 0, max = nil } end
  local separators = value.separators or {
    attached = value.attached or { "=" },
    detached = value.detached ~= false,
    adjacent = value.adjacent == true,
  }
  local accepted_separators = {}
  for _, text in ipairs(separators.attached or {}) do table.insert(accepted_separators, text) end
  if separators.adjacent then table.insert(accepted_separators, "") end
  if separators.detached then table.insert(accepted_separators, " ") end
  return {
    _tag = "declaration", kind = "option", names = opts.aliases,
    result_key = opts.key, explicit_result_key = true, schema = value.schema, form = opts.form,
    occurrence = occurs, values = { min = 1, max = 1 },
    aggregate = opts.occurs and (opts.occurs.max == "many" or (type(opts.occurs.max) == "number" and opts.occurs.max > 1)) and "array" or "scalar",
    separator_policy = { separators = accepted_separators, trim = value.trim ~= false },
    completion = opts.complete,
  }
end

---Declares a boolean flag.
---Default occurrence: 0..1
---Default values: 0..0
---Default aggregate: "scalar"
---Absent: false, Present: true
function M.flag(opts)
  if type(opts) ~= "table" or opts.key == nil then
    error("c.flag requires { key = ..., aliases = { ... } }")
  end
  if not util.is_array(opts.aliases or {}) or #opts.aliases == 0 then
    error("c.flag aliases must be a non-empty array")
  end
  validate_aliases("flag", opts.aliases)
  nonblank_string(opts.key, "c.flag key")
  return {
    _tag = "declaration", kind = "flag", names = opts.aliases,
    result_key = opts.key, explicit_result_key = true,
    occurrence = opts.occurs or { min = 0, max = 1 },
    values = { min = 0, max = 0 }, aggregate = "scalar", default = false,
    metadata = opts.metadata or {}, completion = opts.complete,
  }
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
  key = key or "passthrough"
  nonblank_string(key, "c.passthrough key")
  return {
    _tag = "passthrough",
    key = key,
  }
end

---Selects how a tail declaration forwards its terminator and remaining tokens.
---@param mode "trimmed"|"complete"
function M.forward(mode)
  if type(mode) ~= "string" then
    error("c.forward mode must be 'trimmed' or 'complete'")
  end
  mode = mode:match("^%s*(.-)%s*$")
  if mode ~= "trimmed" and mode ~= "complete" then
    error("c.forward mode must be 'trimmed' or 'complete'")
  end
  return { _tag = "forward", mode = mode }
end

---Declares a node end marker and raw token capture.
---`opts` must be an array containing exactly one c.forward(...) policy.
function M.tail(name, terminator, opts)
  nonblank_string(name, "c.tail name")
  nonblank_string(terminator, "c.tail terminator")
  if type(opts) ~= "table" or not util.is_array(opts) then
    error("c.tail opts must be an array containing exactly one c.forward(...) policy")
  end

  local forward = nil
  for _, item in ipairs(opts) do
    if type(item) ~= "table" or item._tag ~= "forward" then
      error("c.tail opts only accepts c.forward(...) policies")
    end
    if forward then
      error("c.tail opts must contain exactly one c.forward(...) policy")
    end
    forward = item.mode
  end
  if not forward then
    error("c.tail opts must contain exactly one c.forward(...) policy")
  end

  return {
    _tag = "end",
    result_key = name,
    terminator = terminator,
    forward = forward,
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
