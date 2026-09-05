local M = {}

local Scope = {}
Scope.__index = Scope

function Scope.new(parent, ctx)
  local self = setmetatable({}, Scope)
  self.parent = parent
  self.ctx = ctx
  self.defers = {}
  self.children = {}
  self.processes = {}
  self.unwound = false
  return self
end

---Registers a cleanup callback to be executed on scope unwind in LIFO order.
---@param fn function Cleanup callback
function Scope:defer(fn)
  if type(fn) ~= "function" then
    error("scope:defer requires a function")
  end
  if self.unwound then
    -- If already unwound, run immediately
    pcall(fn)
    return
  end
  table.insert(self.defers, fn)
end

---Spawns a managed process attached to this scope.
---@param opts table Spawn options
---@return table Process handle
function Scope:spawn(opts)
  if not self.ctx then
    error("scope:spawn requires an execution context")
  end
  local proc = self.ctx:spawn(opts)
  table.insert(self.processes, proc)

  -- Register cleanup deferral to terminate process if scope closes while running
  self:defer(function()
    if proc:state() == "running" or proc:state() == "spawning" or proc:state() == "draining" then
      proc:terminate()
      pcall(function() proc:wait() end)
    end
  end)

  return proc
end

---Creates a nested child scope.
---@param fn function Scope execution function
---@return any Result of fn
function Scope:scope(fn)
  local child = Scope.new(self, self.ctx)
  table.insert(self.children, child)

  local ok, res = pcall(fn, child)
  child:unwind(ok and "success" or "error", not ok and res or nil)

  if not ok then
    error(res)
  end
  return res
end

---Executes deterministic unwind of this scope in LIFO order.
---Invariant 23: Deterministic LIFO unwind on success, error, interrupt, termination.
---@param reason string "success" | "error" | "interrupt" | "termination"
---@param err any? Optional error object if unwinding due to error
function Scope:unwind(reason, err)
  if self.unwound then return end
  self.unwound = true

  local unwind_errors = {}

  -- 1. Unwind nested child scopes first
  for i = #self.children, 1, -1 do
    local child = self.children[i]
    local ok, c_err = pcall(function()
      child:unwind(reason, err)
    end)
    if not ok then
      table.insert(unwind_errors, c_err)
    end
  end

  -- 2. Execute deferred callbacks in reverse (LIFO) order
  for i = #self.defers, 1, -1 do
    local fn = self.defers[i]
    local ok, d_err = pcall(fn, reason, err)
    if not ok then
      table.insert(unwind_errors, d_err)
    end
  end

  if #unwind_errors > 0 and reason == "success" then
    error("Error during scope unwind: " .. tostring(unwind_errors[1]))
  end
end

M.Scope = Scope

function M.create_scope(parent, ctx)
  return Scope.new(parent, ctx)
end

return M
