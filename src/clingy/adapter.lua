local util = require("clingy.util")

local M = {}

---Safely requires Valua if available.
local function get_valua()
  local ok, valua = pcall(require, "valua")
  if ok then return valua end
  return nil
end

---Inspects a schema using Valua reflection or Standard Schema v1 metadata.
---@param schema any
---@return table Info { kind: string, description: string?, default: any?, options: string[]? }
function M.inspect_schema(schema)
  if not schema or type(schema) ~= "table" then
    return { kind = "unknown" }
  end

  local valua = get_valua()
  if valua and schema["~standard"] and valua.reflect then
    local ok, ref = pcall(valua.reflect, schema)
    if ok and ref and ref.nodes and ref.root then
      local current = ref.nodes[ref.root]
      while current and current.kind == "pipe" and current.base do
        current = ref.nodes[current.base]
      end

      local kind = current and current.kind or "unknown"
      local desc = nil
      local default_val = nil

      for _, n in pairs(ref.nodes) do
        if n.metadata then
          if n.metadata.description then desc = n.metadata.description end
          if n.metadata.default ~= nil then default_val = n.metadata.default end
        end
      end

      return {
        kind = kind,
        description = desc,
        default = default_val,
        options = current and current.options,
      }
    end
  end

  -- Fallback: inspect ~standard directly
  local std = schema["~standard"]
  if std then
    return {
      kind = std.kind or "unknown",
      description = std.description,
    }
  end

  return { kind = "unknown" }
end

---Performs lexical adaptation from a raw string token to the primitive expected by the schema.
---Section 20: Clingy converts lexical representation into the input form expected by Valua.
---@param token string The raw string token from argv.
---@param schema any The schema associated with the argument/option.
---@return any The coerced value.
function M.coerce(token, schema)
  if type(token) ~= "string" then
    return token
  end

  if not schema then
    return token
  end

  local info = M.inspect_schema(schema)
  local kind = info.kind

  if kind == "integer" then
    if token:match("^[+-]?%d+$") then
      local n = tonumber(token)
      if n and math.tointeger then
        return math.tointeger(n) or n
      end
      return n
    end
    -- If not an integer string, pass string to Valua so Valua issues a type error
    return token
  elseif kind == "number" then
    local n = tonumber(token)
    if n then return n end
    return token
  elseif kind == "boolean" then
    if token == "true" or token == "1" then
      return true
    elseif token == "false" or token == "0" then
      return false
    end
    return token
  end

  return token
end

---Validates a coerced value against a schema.
---@param value any Coerced input value.
---@param schema any Valua schema or validator function.
---@param arg_name string Name of the argument/option for error context.
---@return boolean ok True if valid.
---@return any result Validated/transformed value if ok=true, or list of issues / error message if ok=false.
function M.validate(value, schema, arg_name)
  if not schema then
    return true, value
  end

  if type(schema) == "function" then
    local ok, res = pcall(schema, value)
    if not ok then
      return false, { { message = tostring(res), path = { arg_name } } }
    end
    return true, res ~= nil and res or value
  end

  local std = schema["~standard"]
  if std and type(std.validate) == "function" then
    local res = std.validate(value)
    if res.issues and #res.issues > 0 then
      -- Attach arg_name to path if missing
      for _, issue in ipairs(res.issues) do
        if not issue.path or #issue.path == 0 then
          issue.path = { arg_name }
        end
      end
      return false, res.issues
    end
    return true, res.value ~= nil and res.value or value
  end

  return true, value
end

---Combines lexical coercion and semantic validation.
---@param token string
---@param schema any
---@param arg_name string
---@return boolean ok
---@return any result
function M.adapt_and_validate(token, schema, arg_name)
  local coerced = M.coerce(token, schema)
  return M.validate(coerced, schema, arg_name)
end

return M
