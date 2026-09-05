local util = require("clingy.util")

local M = {}

---Safely requires Valua if available.
local function get_valua()
  local ok, valua = pcall(require, "valua")
  if ok then return valua end
  return nil
end

---Inspects a schema using Valua reflection or Standard Schema v1 metadata.
---Follows base/input schema through pipes, unwraps optional/nullable/annotate wrappers.
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
      local visited = {}

      while current and not visited[current.id] do
        visited[current.id] = true
        if current.kind == "pipe" and current.base and ref.nodes[current.base] then
          current = ref.nodes[current.base]
        elseif current.wrapped and ref.nodes[current.wrapped] then
          current = ref.nodes[current.wrapped]
        elseif current.kind == "lazy" and current.inner and ref.nodes[current.inner] then
          current = ref.nodes[current.inner]
        else
          break
        end
      end

      local kind = current and current.kind or "unknown"
      local desc = nil
      local default_val = nil
      local options = current and current.options or nil

      for _, n in pairs(ref.nodes) do
        if n.metadata then
          if n.metadata.description then desc = n.metadata.description end
          if n.metadata.default ~= nil then default_val = n.metadata.default end
        end
      end

      -- Literal inspection
      if kind == "literal" and current and current.value ~= nil then
        local vt = type(current.value)
        if vt == "number" then
          kind = (math.tointeger and math.tointeger(current.value)) and "integer" or "number"
        elseif vt == "boolean" then
          kind = "boolean"
        elseif vt == "string" then
          kind = "string"
        end
      end

      -- Picklist inspection (numeric/boolean picklists)
      if kind == "picklist" and options and #options > 0 then
        local all_int = true
        local all_num = true
        local all_bool = true
        for _, opt in ipairs(options) do
          if type(opt) ~= "number" then
            all_num = false
            all_int = false
          elseif math.tointeger and not math.tointeger(opt) then
            all_int = false
          end
          if type(opt) ~= "boolean" then
            all_bool = false
          end
        end
        if all_int then
          kind = "integer"
        elseif all_num then
          kind = "number"
        elseif all_bool then
          kind = "boolean"
        end
      end

      -- Union inspection
      if kind == "union" and current and current.variants then
        local all_int = true
        local all_num = true
        for _, var_id in ipairs(current.variants) do
          local var_node = ref.nodes[var_id]
          if var_node then
            if var_node.kind ~= "integer" then all_int = false end
            if var_node.kind ~= "number" and var_node.kind ~= "integer" then all_num = false end
          else
            all_int = false
            all_num = false
          end
        end
        if all_int then
          kind = "integer"
        elseif all_num then
          kind = "number"
        else
          kind = "string"
        end
      end

      return {
        kind = kind,
        description = desc,
        default = default_val,
        options = options,
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
    local lower = token:lower()
    if lower == "true" or lower == "1" or lower == "yes" or lower == "on" then
      return true
    elseif lower == "false" or lower == "0" or lower == "no" or lower == "off" then
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
