--[[
  src/clingy/completion/context.lua
  CompletionContext and Sterile Execution Sandbox.
]]

local response = require("clingy.completion.response")
local util = require("clingy.util")

local M = {}

local ContextMethods = {}
ContextMethods.__index = ContextMethods

---Constructs a CompletionContext.
---@param opts { args?: table, prefix?: string, route?: table, target_node?: table, binding?: table, cwd?: string, env?: table, words?: string[], cword?: integer }
---@return table CompletionContext
function M.create(opts)
  opts = opts or {}

  local cwd = opts.cwd
  if not cwd then
    local ok_lfs, lfs = pcall(require, "lfs")
    if ok_lfs and lfs and lfs.currentdir then
      cwd = lfs.currentdir()
    else
      cwd = os.getenv("PWD") or "."
    end
  end

  local env = opts.env
  if not env then
    env = setmetatable({}, {
      __index = function(_, k)
        return os.getenv(k)
      end,
    })
  end

  local raw_args = opts.args or {}
  local args_dual = util.create_args_table(raw_args)

  local ctx = setmetatable({
    args = args_dual,
    prefix = opts.prefix or "",
    route = opts.route or {},
    target_node = opts.target_node,
    binding = opts.binding,
    cwd = cwd,
    env = env,
    words = opts.words or {},
    cword = opts.cword or 1,
  }, ContextMethods)

  return ctx
end

---Safely executes a dynamic provider in a sterile sandbox.
---Suppresses stdout/stderr, intercepts errors, and ensures zero noise.
---@param fn fun(ctx: table): any
---@param ctx table CompletionContext
---@return table CompletionResponse
function M.sandbox_execute(fn, ctx)
  if type(fn) ~= "function" then
    return response.create()
  end

  local orig_print = print
  local orig_io_write = io.write
  local file_mt = getmetatable(io.stdout)
  local file_index = file_mt and file_mt.__index
  local orig_file_write = type(file_index) == "table" and file_index.write or nil

  local dummy_write = function() end

  print = dummy_write
  io.write = dummy_write
  if file_index and orig_file_write then
    pcall(function() file_index.write = dummy_write end)
  end

  local ok, res = pcall(fn, ctx)

  -- Restore I/O functions
  print = orig_print
  io.write = orig_io_write
  if file_index and orig_file_write then
    pcall(function() file_index.write = orig_file_write end)
  end

  if not ok or res == nil then
    return response.create()
  end

  if type(res) == "table" and res._tag == "completion_response" then
    return res
  end

  if type(res) == "table" then
    local resp = response.create()
    for _, item in ipairs(res) do
      resp:add(item)
    end
    return resp
  end

  return response.create()
end

return M
