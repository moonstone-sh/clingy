local M = {}

---@class clingy.PresentationHost
---@field _host_state "created"|"started"|"active"|"suspended"|"finished"|"closed"
local PresentationHost = {}
PresentationHost.__index = PresentationHost

function PresentationHost.new()
  local self = setmetatable({}, PresentationHost)
  self._host_state = "created"
  return self
end

---Returns the current lifecycle state of the presentation host.
---@return "created"|"started"|"active"|"suspended"|"finished"|"closed"
function PresentationHost:state()
  return self._host_state or "created"
end

---Called once during invocation bootstrap prior to argument parsing.
---@param invocation { invocation_id: string, app_name: string, version: string, argv: string[] }
function PresentationHost:start(invocation)
  if self._host_state == "closed" or self._host_state == "finished" then
    error(string.format("Cannot start PresentationHost: host is already %s", self._host_state), 2)
  end
  self._host_state = "started"
end

---Receives canonical semantic events conforming to clingy.events.v1.
---@param event table
function PresentationHost:handle_event(event)
  if self._host_state == "closed" then
    error("Cannot handle event: PresentationHost is already closed", 2)
  end
  if self._host_state == "started" then
    self._host_state = "active"
  end
end

---Flushes all buffered output streams.
function PresentationHost:flush()
  -- Default no-op
end

---Suspends presentation and releases terminal control.
---@param reason? { reason: string, process?: any }
function PresentationHost:suspend(reason)
  if self._host_state == "suspended" then
    error("Cannot suspend PresentationHost: host is already suspended", 2)
  end
  if self._host_state == "closed" or self._host_state == "created" then
    error(string.format("Cannot suspend PresentationHost: host is in state %s", tostring(self._host_state)), 2)
  end
  self._host_state = "suspended"
end

---Resumes presentation and re-acquires terminal control.
function PresentationHost:resume()
  if self._host_state ~= "suspended" then
    error(string.format("Cannot resume PresentationHost: host is not suspended (current state: %s)", tostring(self._host_state)), 2)
  end
  self._host_state = "active"
end

---Handles an interactive prompt request.
---@param request { type: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }
---@return any
function PresentationHost:prompt(request)
  local prompt_mod = require("clingy.presentation.prompt")
  return prompt_mod.fallback(request)
end

---Called once during execution finalization with invocation result.
---@param result { status: "ok"|"failed"|"interrupted", exit_code: integer, error?: any }
function PresentationHost:finish(result)
  if self._host_state == "closed" then
    error("Cannot finish PresentationHost: host is already closed", 2)
  end
  self._host_state = "finished"
end

---Releases all host resources, terminal modes, and background tasks.
---Guaranteed to execute via structured scope deferral.
function PresentationHost:close()
  if self._host_state == "closed" then
    return
  end
  self._host_state = "closed"
end

---Validates whether an object conforms to the PresentationHost interface.
---@param obj any
---@return boolean
function M.is_host(obj)
  if type(obj) ~= "table" then
    return false
  end
  -- Must have handle_event method at minimum
  return type(obj.handle_event) == "function"
end

M.PresentationHost = PresentationHost

return M
