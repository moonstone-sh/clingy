local host_mod = require("clingy.presentation.host")
local prompt_mod = require("clingy.presentation.prompt")

local M = {}

local function encode_json(val)
  local t = type(val)
  if t == "nil" then
    return "null"
  elseif t == "boolean" then
    return val and "true" or "false"
  elseif t == "number" then
    if val ~= val or val == math.huge or val == -math.huge then return "null" end
    return tostring(val)
  elseif t == "string" then
    local s = val:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t')
    return '"' .. s .. '"'
  elseif t == "table" then
    local is_arr = true
    local count = 0
    for k, _ in pairs(val) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
        is_arr = false
      end
    end
    if is_arr and count == #val then
      local parts = {}
      for i = 1, #val do
        table.insert(parts, encode_json(val[i]))
      end
      return "[" .. table.concat(parts, ",") .. "]"
    else
      local keys = {}
      for k in pairs(val) do table.insert(keys, tostring(k)) end
      table.sort(keys)
      local parts = {}
      for _, k in ipairs(keys) do
        table.insert(parts, encode_json(k) .. ":" .. encode_json(val[k]))
      end
      return "{" .. table.concat(parts, ",") .. "}"
    end
  else
    return '"' .. tostring(val) .. '"'
  end
end

M.encode_json = encode_json

---@class clingy.ComposerHost: clingy.PresentationHost
local ComposerHost = setmetatable({}, { __index = host_mod.PresentationHost })
ComposerHost.__index = ComposerHost

function ComposerHost.new(opts)
  opts = opts or {}
  local self = setmetatable({}, ComposerHost)

  local raw_mode = opts.mode or "auto"
  if raw_mode == "json" then
    raw_mode = "ndjson"
  end
  self.mode = raw_mode

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
  if self.capture_mode then
    self.out_sink = opts.stdout
    self.err_sink = opts.stderr
  else
    self.out_sink = opts.stdout or io.stdout
    self.err_sink = opts.stderr or io.stderr
  end

  self.captured_lines = {}
  self.captured_events = {}
  self.reported_tasks = {}
  self._host_state = "created"
  self.is_suspended = false
  self.is_closed = false

  return self
end

function ComposerHost:write_out(str)
  if self.is_suspended then return end
  if self.capture_mode then
    table.insert(self.captured_lines, str)
  end
  if self.out_sink then
    pcall(function()
      self.out_sink:write(str .. "\n")
      self.out_sink:flush()
    end)
  end
end

function ComposerHost:write_err(str)
  if self.is_suspended then return end
  if self.capture_mode then
    table.insert(self.captured_lines, str)
  end
  if self.err_sink then
    pcall(function()
      self.err_sink:write(str .. "\n")
      self.err_sink:flush()
    end)
  end
end

---PresentationHost Lifecycle: start
function ComposerHost:start(invocation)
  host_mod.PresentationHost.start(self, invocation)
  self.invocation = invocation
end

---PresentationHost Lifecycle: handle_event
function ComposerHost:handle_event(evt)
  host_mod.PresentationHost.handle_event(self, evt)
  if self.is_suspended then return end
  table.insert(self.captured_events, evt)

  if self.mode == "ndjson" or self.mode == "json" then
    local json_str = encode_json(evt)
    self:write_out(json_str)
    return
  end

  if self.mode == "quiet" then
    if evt.type == "log" and (evt.level == "error" or evt.level == "fatal") then
      self:write_err(tostring(evt.message))
    elseif evt.type == "result" then
      if type(evt.data) == "string" then
        self:write_out(evt.data)
      elseif evt.message then
        self:write_out(evt.message)
      end
    elseif evt.type == "diagnostic" then
      self:write_err(tostring(evt.message))
    end
    return
  end

  if self.mode == "plain" then
    if evt.type == "span_start" then
      self:write_out("Starting: " .. tostring(evt.name))
    elseif evt.type == "span_end" then
      self:write_out("Finished: " .. tostring(evt.name) .. " (" .. tostring(evt.status) .. ")")
    elseif evt.type == "milestone" then
      self:write_out("=> " .. tostring(evt.message))
    elseif evt.type == "progress" then
      local task = evt.task or "task"
      if not self.reported_tasks[task] then
        self.reported_tasks[task] = true
        if evt.message then
          self:write_out(tostring(evt.message))
        end
      end
    elseif evt.type == "log" then
      local level_str = evt.level and string.upper(evt.level) or "INFO"
      if evt.level == "error" or evt.level == "fatal" then
        self:write_err("[" .. level_str .. "] " .. tostring(evt.message))
      else
        self:write_out("[" .. level_str .. "] " .. tostring(evt.message))
      end
    elseif evt.type == "result" then
      if type(evt.data) == "string" then
        self:write_out(evt.data)
      elseif evt.message then
        self:write_out(evt.message)
      end
    elseif evt.type == "diagnostic" then
      self:write_err("[DIAGNOSTIC] " .. tostring(evt.message))
    end
    return
  end

  if self.mode == "fancy" then
    if evt.type == "span_start" then
      self:write_out("• " .. tostring(evt.name) .. "...")
    elseif evt.type == "span_end" then
      local symbol = evt.status == "ok" and "✔" or "✖"
      self:write_out(symbol .. " " .. tostring(evt.name) .. " (" .. tostring(evt.duration_ms or 0) .. "ms)")
    elseif evt.type == "milestone" then
      self:write_out("==> " .. tostring(evt.message))
    elseif evt.type == "progress" then
      if evt.percentage then
        self:write_out(string.format("[%3d%%] %s", math.floor(evt.percentage), tostring(evt.message or evt.task or "")))
      else
        self:write_out("... " .. tostring(evt.message or ""))
      end
    elseif evt.type == "log" then
      local prefix = "[INFO]"
      if evt.level == "warn" then prefix = "[WARN]"
      elseif evt.level == "error" or evt.level == "fatal" then prefix = "[ERROR]" end
      if evt.level == "error" or evt.level == "fatal" then
        self:write_err(prefix .. " " .. tostring(evt.message))
      else
        self:write_out(prefix .. " " .. tostring(evt.message))
      end
    elseif evt.type == "result" then
      if type(evt.data) == "string" then
        self:write_out(evt.data)
      elseif evt.message then
        self:write_out(evt.message)
      end
    elseif evt.type == "diagnostic" then
      self:write_err("! " .. tostring(evt.message))
    end
    return
  end
end

---PresentationHost Lifecycle: flush
function ComposerHost:flush()
  if self.out_sink and self.out_sink.flush then
    pcall(function() self.out_sink:flush() end)
  end
  if self.err_sink and self.err_sink.flush then
    pcall(function() self.err_sink:flush() end)
  end
end

---PresentationHost Lifecycle: suspend
function ComposerHost:suspend(reason)
  host_mod.PresentationHost.suspend(self, reason)
  self:flush()
  self.is_suspended = true
  if self.is_tty and self.mode == "fancy" and not self.capture_mode then
    self.out_sink:write("\n")
    self.out_sink:flush()
  end
end

---PresentationHost Lifecycle: resume
function ComposerHost:resume()
  host_mod.PresentationHost.resume(self)
  self.is_suspended = false
end

---PresentationHost Lifecycle: prompt
function ComposerHost:prompt(request)
  request = request or {}
  if self.mode == "ndjson" or self.mode == "json" or self.mode == "quiet" or not self.is_tty then
    return prompt_mod.fallback(request)
  end
  return prompt_mod.terminal_prompt(request, self.out_sink, self.is_tty)
end

---PresentationHost Lifecycle: finish
function ComposerHost:finish(result)
  host_mod.PresentationHost.finish(self, result)
  self:flush()
end

---PresentationHost Lifecycle: close
function ComposerHost:close()
  if self._host_state == "closed" then return end
  host_mod.PresentationHost.close(self)
  self:flush()
  self.is_closed = true
end

---Backward compatibility: confirm
function ComposerHost:confirm(prompt, opts)
  opts = opts or {}
  return self:prompt({
    type = "confirm",
    prompt = prompt,
    default = opts.default ~= nil and opts.default or false,
    timeout_ms = opts.timeout_ms,
  })
end

---Backward compatibility: attach
function ComposerHost:attach(event_bus)
  event_bus:on_any(function(evt)
    self:handle_event(evt)
  end)
end

---Backward compatibility: cancel_prompt
function ComposerHost:cancel_prompt()
  self._prompt_cancelled = true
end

M.Composer = ComposerHost
M.ComposerHost = ComposerHost

function M.create_composer(opts)
  return ComposerHost.new(opts)
end

return M
