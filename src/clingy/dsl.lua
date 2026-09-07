local util = require("clingy.util")
local adapter = require("clingy.adapter")
local providers = require("clingy.completion.providers")

local M = {}

local function nonblank_string(value, subject)
  if type(value) ~= "string" or value:match("^%s*$") then
    error(subject .. " must be a string containing non-whitespace characters")
  end
  return value
end

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
  for _, item in ipairs(items) do
    if type(item) == "table" and item._tag == "declaration" and item.kind == "define" then
      error("c.define cannot be inherited; definition records are local to one command segment")
    end
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
  nonblank_string(name, "c.arg name")
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

---Declares a schema-bearing capture fragment for c.compose.
---Captures must be labelled by c.label before they are placed in a pattern.
function M.capture(schema)
  return {
    _tag = "capture",
    schema = schema,
  }
end

---Declares exact fixed text in a c.compose pattern.
function M.literal(text)
  nonblank_string(text, "c.literal text")
  return {
    _tag = "literal",
    text = text,
  }
end

---Declares a one-token positional pattern with labelled captures.
function M.compose(...)
  local items = { ... }
  if #items == 1 and type(items[1]) == "table" and items[1]._tag == nil and util.is_array(items[1]) then
    items = items[1]
  end
  return {
    _tag = "compose",
    items = items,
    occurrence = { min = 1, max = 1 },
    aggregate = "scalar",
  }
end

local function is_named_alias(value)
  return type(value) == "string" and value:sub(1, 1) == "-"
end

local function validate_aliases(kind, names)
  if #names == 0 then
    error(string.format("c.%s requires at least one flag/option alias starting with '-'", kind))
  end

  for _, name in ipairs(names) do
    if name == "-" or name == "--" then
      error(string.format("c.%s alias '%s' is not a usable option or flag spelling", kind, name))
    end
  end
end

---Declares a named option with a value.
---Use c.option("result_key", "--long", "-s", schema) to set the result key
---explicitly. The legacy c.option("--long", "-s", schema) form derives it.
---Default occurrence: 0..1
---Default values: 1..1
---Default aggregate: "scalar"
function M.option(...)
  local args = { ... }
  local names = {}
  local explicit_key = nil
  local schema = nil
  local has_schema = false

  -- The key-first spelling is unambiguous and leaves all alias-only calls on
  -- their historical path, including schemas placed before aliases.
  if type(args[1]) == "string" and not is_named_alias(args[1]) then
    if args[1] == "" then
      error("c.option result_key must be a non-empty string")
    end
    explicit_key = args[1]

    for i = 2, #args do
      local a = args[i]
      if is_named_alias(a) then
        table.insert(names, a)
      elseif has_schema then
        error("c.option accepts at most one schema after its result_key and aliases")
      elseif i ~= #args then
        error("c.option schema must be the final non-name argument when result_key is explicit")
      else
        schema = a
        has_schema = true
      end
    end
  else
    -- Compatibility path: legacy option declarations derive the key solely
    -- from aliases and retain the prior permissive schema placement behavior.
    for _, a in ipairs(args) do
      if is_named_alias(a) then
        table.insert(names, a)
      else
        schema = a
      end
    end
  end

  validate_aliases("option", names)

  local key = explicit_key or util.derive_key(names)

  return {
    _tag = "declaration",
    kind = "option",
    names = names,
    result_key = key,
    explicit_result_key = explicit_key ~= nil,
    schema = schema,
    occurrence = { min = 0, max = 1 },
    values = { min = 1, max = 1 },
    aggregate = "scalar",
  }
end

---Declares a boolean flag.
---Use c.flag("result_key", "--long", "-s") to set the result key
---explicitly. The legacy c.flag("--long", "-s") form derives it.
---Default occurrence: 0..1
---Default values: 0..0
---Default aggregate: "scalar"
---Absent: false, Present: true
function M.flag(...)
  local args = { ... }
  local names = {}
  local metadata = nil
  local explicit_key = nil
  for _, a in ipairs(args) do
    if is_named_alias(a) then
      table.insert(names, a)
    elseif type(a) == "string" then
      if a == "" then
        error("c.flag result_key must be a non-empty string")
      elseif explicit_key then
        error("c.flag accepts only one explicit result_key")
      else
        explicit_key = a
      end
    elseif type(a) == "table" and not a._tag then
      if metadata then
        error("c.flag accepts at most one metadata table")
      end
      metadata = a
    else
      error(string.format("c.flag expects aliases beginning with '-', an optional result_key, and optional metadata; got: %s", tostring(a)))
    end
  end

  validate_aliases("flag", names)

  local key = explicit_key or util.derive_key(names)

  return {
    _tag = "declaration",
    kind = "flag",
    names = names,
    result_key = key,
    explicit_result_key = explicit_key ~= nil,
    occurrence = { min = 0, max = 1 },
    values = { min = 0, max = 0 },
    aggregate = "scalar",
    default = false,
    metadata = metadata or {},
  }
end

---Sets the handler-facing result key of a declaration.
---Supports c.label("result_key", decl) and c.label(decl, "result_key").
---A declaration has one logical label at most; key-first c.flag/c.option
---declarations are already explicitly labelled and cannot be relabelled.
function M.label(a, b)
  local label, decl = a, b
  if type(a) == "table" and (a._tag == "declaration" or a._tag == "capture") then
    decl, label = a, b
  end

  nonblank_string(label, "c.label label")
  if type(decl) == "table" and decl._tag == "capture" then
    if decl.label then
      error("c.label may be applied to a capture exactly once")
    end
    local capture = util.deep_copy(decl)
    capture._inner = decl
    capture.label = label
    capture.source = decl
    return capture
  end
  if type(decl) ~= "table" or decl._tag ~= "declaration"
      or (decl.kind ~= "arg" and decl.kind ~= "option" and decl.kind ~= "flag" and decl.kind ~= "define") then
    error("c.label must wrap a c.arg, c.option, c.flag, or c.define declaration")
  end
  if decl.explicit_result_key then
    error("c.label cannot wrap a declaration with an explicit result_key")
  end
  if decl.logical_label then
    error("c.label may be applied to a declaration exactly once")
  end

  local d = util.deep_copy(decl)
  d._inner = decl
  d.result_key = label
  d.logical_label = true
  return d
end

local function normalize_separator(separator, allow_adjacent)
  if type(separator) ~= "string" then
    error("c.separator entries must be strings")
  end

  -- The empty string is a deliberate, zero-width attached-value separator.
  -- Do not extend that privilege to whitespace-only strings: those are still
  -- invalid ambiguous spellings rather than adjacency.
  if separator == "" then
    if allow_adjacent then
      return separator
    end
    error("c.separator does not accept blank or empty separators")
  end

  -- A single ASCII space is the detached-value spelling. All other separator
  -- declarations are normalized before validation.
  if separator == " " then
    return separator
  end

  local normalized = separator:match("^%s*(.-)%s*$")
  if normalized == "" then
    error("c.separator does not accept blank or empty separators")
  end
  if normalized:find("%s") or not normalized:match("^%p+$") then
    error("c.separator attached separators must be punctuation (or exactly one space for detached values)")
  end
  return normalized
end

---Declares the only value spellings accepted by an option.
---`" "` means a detached next argv token; `""` means an adjacent value;
---punctuation separators are attached.
---Attached values are trimmed by default; pass `{ trim = false }` to preserve
---their surrounding whitespace.
function M.separator(separators, decl, opts)
  -- The one-argument/two-argument fragment form belongs to c.compose. Keep
  -- the established three-argument option wrapper intact.
  if decl == nil or (type(decl) == "table" and decl._tag ~= "declaration") then
    local fragment_opts = decl
    local supplied
    if type(separators) == "string" then
      supplied = { separators }
    elseif type(separators) == "table" and util.is_array(separators) then
      supplied = separators
    else
      error("c.separator pattern fragments must be a punctuation string or array of separator strings")
    end
    if #supplied == 0 then
      error("c.separator pattern fragments cannot be empty")
    end
    if fragment_opts ~= nil then
      if type(fragment_opts) ~= "table" then
        error("c.separator pattern opts must be a table such as { trim = false }")
      end
      for key, value in pairs(fragment_opts) do
        if key ~= "trim" or type(value) ~= "boolean" then
          error("c.separator pattern opts only accepts boolean trim")
        end
      end
    end
    local normalized = {}
    local seen = {}
    for _, separator in ipairs(supplied) do
      local text = normalize_separator(separator)
      if seen[text] then
        error(string.format("c.separator pattern fragments do not accept duplicate separator '%s'", text))
      end
      seen[text] = true
      table.insert(normalized, text)
    end

    -- A separator list is a record-grammar fragment. A scalar keeps the
    -- established c.compose fragment representation and semantics.
    if type(separators) == "table" then
      return { _tag = "define_separator", separators = normalized }
    end
    if normalized[1] == " " then
      error("c.separator pattern fragments cannot be a detached-value space")
    end
    return {
      _tag = "compose_separator",
      text = normalized[1],
      trim = not fragment_opts or fragment_opts.trim ~= false,
    }
  end

  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.separator must wrap a declaration")
  end
  if decl.kind == "flag" then
    error("c.separator cannot wrap a flag because flags consume zero values")
  end
  if decl.kind ~= "option" then
    error("c.separator may only wrap a c.option declaration")
  end
  if opts ~= nil then
    if type(opts) ~= "table" or not util.is_array(opts) and opts.trim == nil then
      error("c.separator opts must be a table such as { trim = false }")
    end
    for key, value in pairs(opts) do
      if key ~= "trim" or type(value) ~= "boolean" then
        error("c.separator opts only accepts boolean trim")
      end
    end
  end

  local supplied
  if type(separators) == "string" then
    supplied = { separators }
  elseif type(separators) == "table" and util.is_array(separators) then
    supplied = separators
  else
    error("c.separator requires a separator string or array of separator strings")
  end
  if #supplied == 0 then
    error("c.separator does not accept an empty separator list")
  end

  local normalized = {}
  local seen = {}
  for _, separator in ipairs(supplied) do
    local value = normalize_separator(separator, true)
    if seen[value] then
      error(string.format("c.separator does not accept duplicate separator '%s'", value))
    end
    seen[value] = true
    table.insert(normalized, value)
  end

  local d = util.deep_copy(decl)
  d._inner = decl
  d.separator_policy = {
    separators = normalized,
    trim = not opts or opts.trim ~= false,
  }
  return d
end

---Declares a compiler-style, two-field definition record.
---The prefix and name are one mandatory adjacent argv fragment. The supplied
---separator grammar then separates that name from its mandatory value.
function M.define(prefix, fragments)
  nonblank_string(prefix, "c.define prefix")
  if prefix:sub(1, 1) ~= "-" or prefix:find("%s") then
    error("c.define prefix must be an exact non-whitespace string starting with '-'")
  end
  if type(fragments) ~= "table" or not util.is_array(fragments) or #fragments ~= 3 then
    error("c.define requires exactly c.label('name', c.capture(...)), c.separator({...}), c.label('value', c.capture(...))")
  end

  local name, separator, value = fragments[1], fragments[2], fragments[3]
  local function validate_capture(item, expected_label)
    if type(item) ~= "table" or item._tag ~= "capture" or item.label ~= expected_label then
      error(string.format("c.define requires labelled '%s' c.capture(...) fragments in order", expected_label))
    end
    if type(item.label) ~= "string" or item.label:match("^%s*$") then
      error("c.define capture labels must be nonblank")
    end
  end
  validate_capture(name, "name")
  validate_capture(value, "value")
  if name.label == value.label then
    error(string.format("c.define does not accept duplicate capture label '%s'", name.label))
  end
  if type(separator) ~= "table" or separator._tag ~= "define_separator"
      or type(separator.separators) ~= "table" or #separator.separators == 0 then
    error("c.define requires c.separator({...}) between its name and value captures")
  end

  local attached = {}
  local detached = false
  for _, text in ipairs(separator.separators) do
    if text == " " then
      detached = true
    else
      table.insert(attached, text)
    end
  end

  return {
    _tag = "declaration",
    kind = "define",
    result_key = util.derive_key({ prefix }),
    names = { prefix },
    occurrence = { min = 0, max = 1 },
    values = { min = 1, max = 1 },
    aggregate = "scalar",
    define_pattern = {
      prefix = prefix,
      name = { label = name.label, schema = name.schema, source = name.source },
      value = { label = value.label, schema = value.schema, source = value.source },
      separators = separator.separators,
      attached = attached,
      detached = detached,
    },
  }
end

---Cardinality modifier: sets occurrence.min = 0. Preserves occurrence.max.
function M.optional(decl)
  if type(decl) == "table" and decl._tag == "compose" then
    error("c.optional cannot wrap c.compose; composed patterns are fixed one-token positionals")
  end
  if type(decl) == "table" and decl._tag == "declaration" and decl.kind == "define" then
    error("c.optional cannot wrap c.define; use c.repeated(c.define(...)) for zero-or-more records")
  end
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
  if type(decl) == "table" and decl._tag == "compose" then
    error("c.required cannot wrap c.compose; composed patterns are already required")
  end
  if type(decl) == "table" and decl._tag == "declaration" and decl.kind == "define" then
    error("c.required cannot wrap c.define; use c.repeated(c.define(...))")
  end
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
  if type(decl) == "table" and decl._tag == "compose" then
    error("c.repeated cannot wrap c.compose; composed patterns are fixed one-token positionals")
  end
  if type(decl) ~= "table" or decl._tag ~= "declaration" then
    error("c.repeated must wrap a declaration (c.arg, c.option, c.flag, c.define)")
  end
  if decl.kind == "define" and decl.define_repeated then
    error("c.repeated may wrap a c.define exactly once")
  end
  local d = util.deep_copy(decl)
  d._inner = decl
  d.occurrence = d.occurrence or { min = 1, max = 1 }
  d.occurrence.max = nil
  if d.kind ~= "flag" then
    d.aggregate = "array"
  end
  if d.kind == "define" then
    d.define_repeated = true
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

-- `end` is retained as a deprecated compatibility alias; use c.tail instead.
M.end_ = M.tail
M["end"] = M.tail

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
  if decl.kind == "define" then
    error("c.complete cannot wrap c.define; record-field completion is intentionally conservative")
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
