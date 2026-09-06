local host_mod = require("clingy.presentation.host")
local composer_mod = require("clingy.composer")
local PresentationHost = host_mod.PresentationHost

local M = {}

local ComposerHost = setmetatable({}, { __index = PresentationHost })
ComposerHost.__index = ComposerHost

---Creates a new ComposerHost wrapping the terminal Composer engine.
---@param opts? table Configuration: { mode = "auto"|"fancy"|"plain"|"quiet"|"ndjson"|"json", stdout = ..., stderr = ..., is_tty = ..., capture = ... }
---@return table ComposerHost
function ComposerHost.new(opts)
  opts = opts or {}
  local self = PresentationHost.new(opts)
  setmetatable(self, ComposerHost)

  -- Normalize mode: "json" is an alias for "ndjson"
  local raw_mode = opts.mode or "auto"
  if raw_mode == "json" or raw_mode == "ndjson" then
    self.mode = "ndjson"
  else
    self.mode = raw_mode
  end

  self.is_tty = opts.is_tty
  if self.is_tty == nil then
    local term = os.getenv("TERM")
    local is_ci = os.getenv("CI") ~= nil
    self.is_tty = term ~= nil and term ~= "dumb" and not is_ci
  end

  if self.mode == "auto" then
    if self.is_tty then
      self.mode = "fancy"
    else
      self.mode = "plain"
    end
  end

  self.capture_mode = opts.capture or false
  self.out_sink = opts.stdout or (not self.capture_mode and io.stdout or nil)
  self.err_sink = opts.stderr or (not self.capture_mode and io.stderr or nil)

  -- Underlying Composer instance
  self.composer = composer_mod.create_composer({
    mode = (self.mode == "ndjson") and "json" or self.mode,
    stdout = opts.stdout,
    stderr = opts.stderr,
    is_tty = self.is_tty,
    capture = self.capture_mode,
  })

  -- Mirror captured structures for direct inspection
  self.captured_lines = self.composer.captured_lines
  self.captured_events = self.composer.captured_events

  return self
end

function ComposerHost:captured_lines()
  return self.captured_lines
end

function ComposerHost:captured_events()
  return self.captured_events
end

function ComposerHost:start(invocation_info)
  PresentationHost.start(self, invocation_info)
  return true
end

function ComposerHost:handle_event(evt)
  if not PresentationHost.handle_event(self, evt) then
    return false
  end
  self.composer:handle_event(evt)
  return true
end

function ComposerHost:suspend()
  if not PresentationHost.suspend(self) then return false end
  -- Flush any pending output before yielding terminal control
  pcall(function()
    if self.out_sink and self.out_sink.flush then self.out_sink:flush() end
    if self.err_sink and self.err_sink.flush then self.err_sink:flush() end
  end)
  return true
end

function ComposerHost:resume()
  if not PresentationHost.resume(self) then return false end
  return true
end

function ComposerHost:prompt(req)
  req = req or {}
  local p_type = req.type or "confirm"
  local default_val = req.default

  -- Non-interactive policy: quiet, ndjson, or non-tty environments return deterministic default
  local is_non_interactive = (self.mode == "ndjson" or self.mode == "quiet" or not self.is_tty or self._prompt_cancelled)
  if is_non_interactive then
    if default_val ~= nil then return default_val end
    return (p_type == "confirm") and false or ""
  end

  if p_type == "confirm" then
    local prompt_msg = req.message or "Confirm?"
    return self.composer:confirm(prompt_msg, { default = default_val })
  elseif p_type == "text" then
    local prompt_msg = req.message or "Input:"
    local hint = default_val and (" [" .. tostring(default_val) .. "] ") or " "
    if self.out_sink then
      pcall(function()
        self.out_sink:write(prompt_msg .. hint)
        self.out_sink:flush()
      end)
    end

    local line = io.read("*l")
    if self._prompt_cancelled then
      return default_val or ""
    end

    if not line or line == "" then
      line = default_val or ""
    end

    if req.validate then
      local ok, valid_or_err = pcall(req.validate, line)
      if not ok or not valid_or_err then
        return default_val or line
      end
      if type(valid_or_err) == "string" then
        return valid_or_err
      end
    end

    return line
  end

  return default_val
end

function ComposerHost:confirm(message, opts)
  opts = opts or {}
  return self:prompt({
    type = "confirm",
    message = message,
    default = opts.default,
  })
end

function ComposerHost:cancel_prompt()
  PresentationHost.cancel_prompt(self)
  if self.composer.cancel_prompt then
    self.composer:cancel_prompt()
  end
  return true
end

function ComposerHost:finish(exit_info)
  PresentationHost.finish(self, exit_info)
  pcall(function()
    if self.out_sink and self.out_sink.flush then self.out_sink:flush() end
    if self.err_sink and self.err_sink.flush then self.err_sink:flush() end
  end)
  return true
end

function ComposerHost:close()
  if self:is_closed() then return true end
  pcall(function()
    if self.out_sink and self.out_sink.flush then self.out_sink:flush() end
    if self.err_sink and self.err_sink.flush then self.err_sink:flush() end
  end)
  PresentationHost.close(self)
  return true
end

M.ComposerHost = ComposerHost

function M.create_composer_host(opts)
  return ComposerHost.new(opts)
end

return M
