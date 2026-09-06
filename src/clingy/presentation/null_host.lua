local host_mod = require("clingy.presentation.host")
local prompt_mod = require("clingy.presentation.prompt")

local M = {}

---@class clingy.NullHost: clingy.PresentationHost
local NullHost = setmetatable({}, { __index = host_mod.PresentationHost })
NullHost.__index = NullHost

function NullHost.new()
  local self = setmetatable({}, NullHost)
  self._host_state = "created"
  return self
end

function NullHost:start(invocation)
  host_mod.PresentationHost.start(self, invocation)
end

function NullHost:handle_event(event)
  host_mod.PresentationHost.handle_event(self, event)
end

function NullHost:flush()
  host_mod.PresentationHost.flush(self)
end

function NullHost:suspend(reason)
  host_mod.PresentationHost.suspend(self, reason)
end

function NullHost:resume()
  host_mod.PresentationHost.resume(self)
end

function NullHost:prompt(request)
  return prompt_mod.fallback(request)
end

function NullHost:finish(result)
  host_mod.PresentationHost.finish(self, result)
end

function NullHost:close()
  if self._host_state == "closed" then return end
  host_mod.PresentationHost.close(self)
end

M.NullHost = NullHost

function M.create()
  return NullHost.new()
end

return M
