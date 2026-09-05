--[[
  tests/fixtures/fixture_schema.lua
  Minimal Standard Schema v1 fixture.
  Used to prove Clingy's decoupled architecture and custom schema adapters.
]]

local M = {}

local SchemaMethods = {}
SchemaMethods.__index = SchemaMethods

function SchemaMethods:min(val)
  self.min_val = val
  self.min_len = val
  return self
end

function SchemaMethods:max(val)
  self.max_val = val
  self.max_len = val
  return self
end

function SchemaMethods:default(val)
  self.default = val
  if self["~standard"] then
    self["~standard"].default = val
  end
  return self
end

function SchemaMethods:description(desc)
  self.description = desc
  if self["~standard"] then
    self["~standard"].description = desc
  end
  return self
end

function SchemaMethods:transform(fn)
  return M.transform(self, fn)
end

---Creates a Standard Schema v1 string validator.
---@param opts? { min?: integer, max?: integer, default?: string, description?: string }
function M.string(opts)
  opts = opts or {}
  local schema = setmetatable({
    kind = "string",
    default = opts.default,
    description = opts.description,
    min_len = opts.min,
    max_len = opts.max,
  }, SchemaMethods)

  schema["~standard"] = {
    version = 1,
    vendor = "fixture-validator",
    kind = "string",
    default = opts.default,
    description = opts.description,
    validate = function(value)
      if type(value) ~= "string" then
        return {
          issues = {
            { message = string.format("Expected string, got %s", type(value)) }
          }
        }
      end
      if schema.min_len and #value < schema.min_len then
        return {
          issues = {
            { message = string.format("String length must be at least %d", schema.min_len) }
          }
        }
      end
      if schema.max_len and #value > schema.max_len then
        return {
          issues = {
            { message = string.format("String length must be at most %d", schema.max_len) }
          }
        }
      end
      return { value = value }
    end,
  }

  return schema
end

---Creates a Standard Schema v1 integer validator.
---Expects a number (coerced by registered schema adapter).
---@param opts? { min?: integer, max?: integer, default?: integer, description?: string }
function M.integer(opts)
  opts = opts or {}
  local schema = setmetatable({
    kind = "integer",
    default = opts.default,
    description = opts.description,
    min_val = opts.min,
    max_val = opts.max,
  }, SchemaMethods)

  schema["~standard"] = {
    version = 1,
    vendor = "fixture-validator",
    kind = "integer",
    default = opts.default,
    description = opts.description,
    validate = function(value)
      if type(value) ~= "number" then
        return {
          issues = {
            { message = string.format("Expected integer number, got %s (%s)", tostring(value), type(value)) }
          }
        }
      end

      local int_val = math.tointeger and math.tointeger(value)
      if int_val == nil then
        if math.floor(value) ~= value then
          return {
            issues = {
              { message = string.format("Expected integer, got float %s", tostring(value)) }
            }
          }
        end
        int_val = math.floor(value)
      end

      if schema.min_val and int_val < schema.min_val then
        return {
          issues = {
            { message = string.format("Integer %d must be at least %d", int_val, schema.min_val) }
          }
        }
      end

      if schema.max_val and int_val > schema.max_val then
        return {
          issues = {
            { message = string.format("Integer %d must be at most %d", int_val, schema.max_val) }
          }
        }
      end

      return { value = int_val }
    end,
  }

  return schema
end

---Creates a Standard Schema v1 number validator.
---Expects a number (coerced by registered schema adapter).
---@param opts? { min?: number, max?: number, default?: number, description?: string }
function M.number(opts)
  opts = opts or {}
  local schema = setmetatable({
    kind = "number",
    default = opts.default,
    description = opts.description,
    min_val = opts.min,
    max_val = opts.max,
  }, SchemaMethods)

  schema["~standard"] = {
    version = 1,
    vendor = "fixture-validator",
    kind = "number",
    default = opts.default,
    description = opts.description,
    validate = function(value)
      if type(value) ~= "number" then
        return {
          issues = {
            { message = string.format("Expected number, got %s (%s)", tostring(value), type(value)) }
          }
        }
      end

      if schema.min_val and value < schema.min_val then
        return {
          issues = {
            { message = string.format("Number %s must be at least %s", tostring(value), tostring(schema.min_val)) }
          }
        }
      end

      if schema.max_val and value > schema.max_val then
        return {
          issues = {
            { message = string.format("Number %s must be at most %s", tostring(value), tostring(schema.max_val)) }
          }
        }
      end

      return { value = value }
    end,
  }

  return schema
end

---Creates a Standard Schema v1 boolean validator.
---Expects a boolean (coerced by registered schema adapter).
---@param opts? { default?: boolean, description?: string }
function M.boolean(opts)
  opts = opts or {}
  local schema = setmetatable({
    kind = "boolean",
    default = opts.default,
    description = opts.description,
  }, SchemaMethods)

  schema["~standard"] = {
    version = 1,
    vendor = "fixture-validator",
    kind = "boolean",
    default = opts.default,
    description = opts.description,
    validate = function(value)
      if type(value) ~= "boolean" then
        return {
          issues = {
            { message = string.format("Expected boolean, got %s (%s)", tostring(value), type(value)) }
          }
        }
      end

      return { value = value }
    end,
  }

  return schema
end

---Creates a Standard Schema v1 transformer or chains a schema with a transformation function.
---@param base_or_fn any Schema or transform function
---@param maybe_fn? fun(value: any): any
function M.transform(base_or_fn, maybe_fn)
  local base_schema = maybe_fn and base_or_fn or nil
  local fn = maybe_fn or base_or_fn

  if type(fn) ~= "function" then
    error("fixture_schema.transform requires a transform function")
  end

  local schema = setmetatable({
    kind = base_schema and base_schema.kind or "transform",
    default = base_schema and base_schema.default or nil,
    description = base_schema and base_schema.description or nil,
  }, SchemaMethods)

  schema["~standard"] = {
    version = 1,
    vendor = "fixture-validator",
    kind = schema.kind,
    default = schema.default,
    description = schema.description,
    validate = function(value)
      local current_val = value
      if base_schema and base_schema["~standard"] and type(base_schema["~standard"].validate) == "function" then
        local res = base_schema["~standard"].validate(current_val)
        if res.issues and #res.issues > 0 then
          return res
        end
        current_val = res.value ~= nil and res.value or current_val
      end

      local ok, transformed = pcall(fn, current_val)
      if not ok then
        return {
          issues = {
            { message = string.format("Transformation failed: %s", tostring(transformed)) }
          }
        }
      end

      return { value = transformed }
    end,
  }

  return schema
end

return M
