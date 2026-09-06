local host_mod = require("clingy.presentation.host")
local PresentationHost = host_mod.PresentationHost

local M = {}

--------------------------------------------------------------------------------
-- NullHost: completely silent, drops all events, returns defaults for prompts
--------------------------------------------------------------------------------
local NullHost = setmetatable({}, { __index = PresentationHost })
NullHost.__index = NullHost

function NullHost.new(opts)
  local self = PresentationHost.new(opts)
  setmetatable(self, NullHost)
  return self
end

function NullHost:handle_event(evt)
  return true
end

function NullHost:prompt(req)
  req = req or {}
  if req.default ~= nil then
    return req.default
  end
  if req.type == "confirm" then
    return false
  end
  return ""
end

function NullHost:confirm(message, opts)
  opts = opts or {}
  return opts.default ~= nil and opts.default or false
end

--------------------------------------------------------------------------------
-- RecordingHost: structured call and event tracking for testing/telemetry
--------------------------------------------------------------------------------
local RecordingHost = setmetatable({}, { __index = PresentationHost })
RecordingHost.__index = RecordingHost

function RecordingHost.new(opts)
  opts = opts or {}
  local self = PresentationHost.new(opts)
  setmetatable(self, RecordingHost)
  self.calls = {}
  self.events = {}
  self.prompt_response = opts.prompt_response
  self.on_prompt = opts.on_prompt
  return self
end

function RecordingHost:_record(method, ...)
  table.insert(self.calls, {
    method = method,
    args = { ... },
    timestamp = os.time(),
  })
end

function RecordingHost:start(invocation_info)
  self:_record("start", invocation_info)
  return PresentationHost.start(self, invocation_info)
end

function RecordingHost:handle_event(evt)
  self:_record("handle_event", evt)
  table.insert(self.events, evt)
  return PresentationHost.handle_event(self, evt)
end

function RecordingHost:suspend()
  self:_record("suspend")
  return PresentationHost.suspend(self)
end

function RecordingHost:resume()
  self:_record("resume")
  return PresentationHost.resume(self)
end

function RecordingHost:prompt(req)
  self:_record("prompt", req)
  if self.on_prompt then
    return self.on_prompt(req)
  end
  if self.prompt_response ~= nil then
    return self.prompt_response
  end
  return PresentationHost.prompt(self, req)
end

function RecordingHost:confirm(message, opts)
  self:_record("confirm", message, opts)
  if self.on_prompt then
    return self.on_prompt({ type = "confirm", message = message, default = opts and opts.default })
  end
  if self.prompt_response ~= nil then
    return self.prompt_response
  end
  return PresentationHost.confirm(self, message, opts)
end

function RecordingHost:cancel_prompt()
  self:_record("cancel_prompt")
  return PresentationHost.cancel_prompt(self)
end

function RecordingHost:finish(exit_info)
  self:_record("finish", exit_info)
  return PresentationHost.finish(self, exit_info)
end

function RecordingHost:close()
  self:_record("close")
  return PresentationHost.close(self)
end

function RecordingHost:has_call(method)
  for _, c in ipairs(self.calls) do
    if c.method == method then return true end
  end
  return false
end

function RecordingHost:call_count(method)
  local count = 0
  for _, c in ipairs(self.calls) do
    if c.method == method then count = count + 1 end
  end
  return count
end

function RecordingHost:calls_of(method)
  local res = {}
  for _, c in ipairs(self.calls) do
    if c.method == method then table.insert(res, c) end
  end
  return res
end

function RecordingHost:events_of(event_type)
  local res = {}
  for _, evt in ipairs(self.events) do
    if evt.type == event_type then table.insert(res, evt) end
  end
  return res
end

function RecordingHost:find_event(event_type)
  for _, evt in ipairs(self.events) do
    if evt.type == event_type then return evt end
  end
  return nil
end

function RecordingHost:last_event()
  return self.events[#self.events]
end

--------------------------------------------------------------------------------
-- FailingHost: configurable fault injector for error containment verification
--------------------------------------------------------------------------------
local FailingHost = setmetatable({}, { __index = PresentationHost })
FailingHost.__index = FailingHost

function FailingHost.new(opts)
  opts = opts or {}
  local self = PresentationHost.new(opts)
  setmetatable(self, FailingHost)
  self.calls = {}
  self.fail_at = opts.fail_at or {}
  if type(self.fail_at) == "string" then
    self.fail_at = { [opts.fail_at] = true }
  end
  self.error_message = opts.error_message or "FailingHost synthetic failure"
  self.fail_event_type = opts.fail_event_type
  return self
end

function FailingHost:_check_fail(method, extra)
  table.insert(self.calls, { method = method, extra = extra })
  if type(self.fail_at) == "function" then
    if self.fail_at(method, extra) then
      error(self.error_message .. " at " .. method)
    end
  elseif type(self.fail_at) == "table" and self.fail_at[method] then
    if method == "handle_event" and self.fail_event_type then
      if extra and extra.type == self.fail_event_type then
        error(self.error_message .. " at handle_event (" .. tostring(self.fail_event_type) .. ")")
      end
    else
      error(self.error_message .. " at " .. method)
    end
  end
end

function FailingHost:start(invocation_info)
  self:_check_fail("start", invocation_info)
  return PresentationHost.start(self, invocation_info)
end

function FailingHost:handle_event(evt)
  self:_check_fail("handle_event", evt)
  return PresentationHost.handle_event(self, evt)
end

function FailingHost:suspend()
  self:_check_fail("suspend")
  return PresentationHost.suspend(self)
end

function FailingHost:resume()
  self:_check_fail("resume")
  return PresentationHost.resume(self)
end

function FailingHost:prompt(req)
  self:_check_fail("prompt", req)
  return PresentationHost.prompt(self, req)
end

function FailingHost:confirm(message, opts)
  self:_check_fail("confirm", { message = message, opts = opts })
  return PresentationHost.confirm(self, message, opts)
end

function FailingHost:cancel_prompt()
  self:_check_fail("cancel_prompt")
  return PresentationHost.cancel_prompt(self)
end

function FailingHost:finish(exit_info)
  self:_check_fail("finish", exit_info)
  return PresentationHost.finish(self, exit_info)
end

function FailingHost:close()
  self:_check_fail("close")
  return PresentationHost.close(self)
end

M.NullHost = NullHost
M.RecordingHost = RecordingHost
M.FailingHost = FailingHost

return M
