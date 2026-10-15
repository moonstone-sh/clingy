-- Recreates inline Valua schemas as constructor calls, so a declaration can
-- keep writing `schema = v.string()` and still be built. Only a small,
-- function-free subset is attempted, and a schema is accepted only if the
-- recreated copy reflects to exactly the same graph as the original. Anything
-- else must be exported from a runtime module and is referenced instead.
--
-- The emitted code requires Valua's individual modules
-- (`valua.schemas.string`, `valua.actions.min_length`, ...), so a built CLI
-- loads only the schemas it uses.

local serialize = require("clingy.build.serialize")

local M = {}

local SCALARS = { string = true, integer = true, number = true, boolean = true }
local ACTIONS = {
  min_length = "value", max_length = "value", length = "value",
  min_value = "value", max_value = "value", multiple_of = "value",
  pattern = "pattern", starts_with = "prefix", ends_with = "suffix", non_empty = false,
}

local function literal(v)
  local _, expr = serialize.write(v, { expression = function() return nil end })
  return expr
end

-- Constructors take their value (if any) first and the custom message last.
local function message_args(first, message)
  local message_code = message ~= nil and literal(message) or nil
  if first == nil then return message_code or "" end
  return message_code and (first .. ", " .. message_code) or first
end

local function field_names(node)
  local names = {}
  for k in pairs(node) do names[#names + 1] = k end
  return names
end

local function only(node, allowed)
  for _, k in ipairs(field_names(node)) do
    if not allowed[k] then return false end
  end
  return true
end

-- Returns Lua source for the node, or nil when it is outside the subset.
local function emit(graph, id)
  local node = graph.nodes[id]
  if not node then return nil end
  local kind = node.kind
  local code
  if SCALARS[kind] and only(node, { id = true, kind = true, message = true, metadata = true }) then
    code = ("require(%q)(%s)"):format("valua.schemas." .. kind, message_args(nil, node.message))
  elseif kind == "picklist" and only(node, { id = true, kind = true, options = true, message = true, metadata = true }) then
    code = ("require(%q)(%s)"):format("valua.schemas.picklist", message_args(literal(node.options or {}), node.message))
  elseif kind == "literal" and only(node, { id = true, kind = true, value = true, message = true, metadata = true }) then
    code = ("require(%q)(%s)"):format("valua.schemas.literal", message_args(literal(node.value), node.message))
  elseif kind == "optional" and only(node, { id = true, kind = true, wrapped = true, metadata = true }) then
    local inner = emit(graph, node.wrapped)
    if not inner then return nil end
    code = ("require(%q)(%s)"):format("valua.schemas.optional", inner)
  elseif kind == "pipe" and not node.has_transform then
    local base = emit(graph, node.base)
    if not base then return nil end
    local parts = { base }
    for _, constraint in ipairs(node.constraints or {}) do
      local arg = ACTIONS[constraint.kind]
      if arg == nil or constraint.opaque then return nil end
      parts[#parts + 1] = ("require(%q)(%s)"):format("valua.actions." .. constraint.kind,
        message_args(arg and literal(constraint[arg]) or nil, constraint.message))
    end
    code = ("require(%q)(%s)"):format("valua.methods.pipe", table.concat(parts, ", "))
  else
    return nil
  end
  local metadata = node.metadata
  if metadata ~= nil then
    if not only(metadata, { description = true }) or type(metadata.description) ~= "string" then return nil end
    code = ("require(%q)(%s, %s)"):format("valua.methods.describe", code, literal(metadata.description))
  end
  return code
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

---@param schema table A schema whose `~standard.vendor` is "valua".
---@return string? source A constructor expression, or nil if the schema can't be recreated exactly.
function M.recreate(schema)
  local reflect = require("valua.methods.reflect")
  local ok, graph = pcall(reflect, schema)
  if not ok or type(graph) ~= "table" or not graph.nodes then return nil end
  local code = emit(graph, graph.root)
  if not code then return nil end
  local load_chunk = loadstring or load
  local chunk = load_chunk("return " .. code, "=clingy.build")
  if not chunk then return nil end
  local built_ok, copy = pcall(chunk)
  if not built_ok then return nil end
  local copy_ok, copy_graph = pcall(reflect, copy)
  if not copy_ok or not same(graph, copy_graph) then return nil end
  return code
end

return M
