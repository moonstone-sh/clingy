local host_mod = require("clingy.presentation.host")
local prompt_mod = require("clingy.presentation.prompt")

local M = {}

---@class clingy.RecordingHost: clingy.PresentationHost
local RecordingHost = setmetatable({}, { __index = host_mod.PresentationHost })
RecordingHost.__index = RecordingHost

function RecordingHost.new(opts)
  opts = opts or {}
  local self = setmetatable({}, RecordingHost)
  self._host_state = "created"
  self.events = {}
  self.calls = {}
  self.prompts = {}
  self.prompt_responses = opts.prompt_responses or {}
  self.is_closed = false
  self.is_suspended = false
  return self
end

function RecordingHost:_record_call(method, ...)
  table.insert(self.calls, {
    method = method,
    args = { ... },
    timestamp = os.time(),
  })
end

function RecordingHost:start(invocation)
  host_mod.PresentationHost.start(self, invocation)
  self:_record_call("start", invocation)
  self.invocation = invocation
end

function RecordingHost:handle_event(event)
  host_mod.PresentationHost.handle_event(self, event)
  table.insert(self.events, event)
  self:_record_call("handle_event", event)
end

function RecordingHost:flush()
  host_mod.PresentationHost.flush(self)
  self:_record_call("flush")
end

function RecordingHost:suspend(reason)
  host_mod.PresentationHost.suspend(self, reason)
  self.is_suspended = true
  self:_record_call("suspend", reason)
end

function RecordingHost:resume()
  host_mod.PresentationHost.resume(self)
  self.is_suspended = false
  self:_record_call("resume")
end

function RecordingHost:prompt(request)
  table.insert(self.prompts, request)
  self:_record_call("prompt", request)

  if type(self.prompt_responses) == "function" then
    return self.prompt_responses(request)
  elseif type(self.prompt_responses) == "table" and #self.prompt_responses > 0 then
    return table.remove(self.prompt_responses, 1)
  end

  return prompt_mod.fallback(request)
end

function RecordingHost:finish(result)
  host_mod.PresentationHost.finish(self, result)
  self.result = result
  self:_record_call("finish", result)
end

function RecordingHost:close()
  if self._host_state == "closed" then return end
  host_mod.PresentationHost.close(self)
  self.is_closed = true
  self:_record_call("close")
end

M.RecordingHost = RecordingHost

function M.create(opts)
  return RecordingHost.new(opts)
end

return M
