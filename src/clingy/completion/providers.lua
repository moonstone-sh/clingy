--[[
  src/clingy/completion/providers.lua
  Standard Completion Providers: values, path, file, directory, dynamic, none.
]]

local response = require("clingy.completion.response")
local context_mod = require("clingy.completion.context")

local M = {}

---Constructs a static values completion provider.
---@param ... any Table of values/candidates or vararg strings/tables
---@return table Provider
function M.values(...)
  local args = { ... }
  local items = {}

  if #args == 1 and type(args[1]) == "table" and not args[1]._tag then
    items = args[1]
  else
    items = args
  end

  local candidates = {}
  for _, item in ipairs(items) do
    table.insert(candidates, response.candidate(item))
  end

  return {
    _tag = "completion_provider",
    kind = "values",
    candidates = candidates,
    resolve = function(self, ctx)
      local resp = response.create()
      for _, cand in ipairs(self.candidates) do
        resp:add(cand)
      end
      if ctx and ctx.prefix and ctx.prefix ~= "" then
        resp:filter_by_prefix(ctx.prefix)
      end
      return resp
    end,
  }
end

---Constructs a generic path completion provider.
---@param opts? { extensions?: string[], pattern?: string }
---@return table Provider
function M.path(opts)
  opts = opts or {}
  return {
    _tag = "completion_provider",
    kind = "path",
    opts = opts,
    resolve = function(self, ctx)
      local resp = response.create(nil, response.DIRECTIVE.FILENAMES)
      return resp
    end,
  }
end

---Constructs a file completion provider.
---@param opts? { extensions?: string[], pattern?: string }
---@return table Provider
function M.file(opts)
  opts = opts or {}
  return {
    _tag = "completion_provider",
    kind = "file",
    opts = opts,
    resolve = function(self, ctx)
      local resp = response.create(nil, response.DIRECTIVE.FILENAMES)
      return resp
    end,
  }
end

---Constructs a directory completion provider.
---@param opts? table
---@return table Provider
function M.directory(opts)
  opts = opts or {}
  return {
    _tag = "completion_provider",
    kind = "directory",
    opts = opts,
    resolve = function(self, ctx)
      local resp = response.create(nil, response.DIRECTIVE.DIRECTORIES)
      return resp
    end,
  }
end

---Constructs a dynamic callback completion provider.
---@param fn fun(ctx: table): any
---@return table Provider
function M.dynamic(fn)
  assert(type(fn) == "function", "c.dynamic must receive a callback function")
  return {
    _tag = "completion_provider",
    kind = "dynamic",
    fn = fn,
    resolve = function(self, ctx)
      local resp = context_mod.sandbox_execute(self.fn, ctx)
      if ctx and ctx.prefix and ctx.prefix ~= "" then
        resp:filter_by_prefix(ctx.prefix)
      end
      return resp
    end,
  }
end

---Constructs a hard suppression provider.
---Suppresses all completions and informs shell not to fallback to files.
---@return table Provider
function M.none()
  return {
    _tag = "completion_provider",
    kind = "none",
    resolve = function(self, ctx)
      return response.create(nil, response.DIRECTIVE.NO_FILES)
    end,
  }
end

return M
