local host_mod = require("clingy.presentation.host")
local prompt_mod = require("clingy.presentation.prompt")

local M = {}

---@class clingy.FailingHost: clingy.PresentationHost
local FailingHost = setmetatable({}, { __index = host_mod.PresentationHost })
FailingHost.__index = FailingHost

function FailingHost.new(opts)
  opts = opts or {}
  local self = setmetatable({}, FailingHost)
  self.fail_on = opts.fail_on or {}
  self.events = {}
  self.calls = {}
  return self
end

function FailingHost:_check_fail(method)
  table.insert(self.calls, method)
  if self.fail_on[method] then
    error(string.format("Injected host fault on %s: %s", method, tostring(self.fail_on[method])))
  end
end

function FailingHost:start(invocation)
  self:_check_fail("start")
end

function FailingHost:handle_event(event)
  table.insert(self.events, event)
  self:_check_fail("handle_event")
end

function FailingHost:flush()
  self:_check_fail("flush")
end

function FailingHost:suspend(reason)
  self:_check_fail("suspend")
end

function FailingHost:resume()
  self:_check_fail("resume")
end

function FailingHost:prompt(request)
  self:_check_fail("prompt")
  return prompt_mod.fallback(request)
end

function FailingHost:finish(result)
  self:_check_fail("finish")
end

function FailingHost:close()
  self:_check_fail("close")
end

M.FailingHost = FailingHost

function M.create(opts)
  return FailingHost.new(opts)
end

return M
