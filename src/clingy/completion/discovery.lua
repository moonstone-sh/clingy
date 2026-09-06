--[[
  src/clingy/completion/discovery.lua
  Schema-Derived Discovery: Automatic option/argument candidate extraction.
  Strict Precedence: explicit c.complete > schema-derived > no provider (c.none hard suppression).
]]

local adapter = require("clingy.adapter")
local providers = require("clingy.completion.providers")

local M = {}

---Attempts to derive a completion provider from a schema via adapter reflection.
---@param schema any
---@return table? Provider
function M.discover_provider(schema)
  if not schema then
    return nil
  end

  local ok, info = pcall(adapter.inspect_schema, schema)
  if not ok or type(info) ~= "table" then
    return nil
  end

  -- Finite picklist / enum / union options discovered from schema
  if info.options and #info.options > 0 then
    local string_options = {}
    for _, opt in ipairs(info.options) do
      table.insert(string_options, tostring(opt))
    end
    return providers.values(string_options)
  end

  return nil
end

---Resolves the effective completion provider for a binding respecting precedence.
---@param binding table
---@return table? Provider
function M.resolve_binding_completion(binding)
  if not binding then
    return nil
  end

  local comp = binding.completion

  -- 1. Explicit declaration
  if comp and comp.origin == "explicit" and comp.provider then
    return comp.provider
  end

  -- 2. Explicit none suppression
  if comp and comp.origin == "none" then
    return providers.none()
  end

  -- 3. Schema-derived discovery
  if binding.schema then
    local derived = M.discover_provider(binding.schema)
    if derived then
      return derived
    end
  end

  -- 4. No provider
  return nil
end

return M
