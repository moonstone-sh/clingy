local util = require("clingy.util")

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

local Composer = {}
Composer.__index = Composer

function Composer.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Composer)
  self.mode = opts.mode or "auto"
  self.is_tty = opts.is_tty
  if self.is_tty == nil then
    -- Detect TTY or CI
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

  -- Plain mode semantic reduction tracking
  self.reported_tasks = {}

  return self
end

function Composer:write_out(str)
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

function Composer:write_err(str)
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

---Connects Composer to a semantic event bus.
function Composer:attach(event_bus)
  event_bus:on_any(function(evt)
    self:handle_event(evt)
  end)
end

---Handles a semantic event according to the active presentation mode.
function Composer:handle_event(evt)
  table.insert(self.captured_events, evt)

  if self.mode == "json" then
    -- Invariant 24: Stable machine-readable NDJSON stream
    local json_str = encode_json(evt)
    self:write_out(json_str)
    return
  end

  if self.mode == "quiet" then
    -- Suppress progress, normal logs, spans
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
    -- Invariant 21 / Section 39: Plain mode is a semantic reduction, zero ANSI, no tick spam
    if evt.type == "span_start" then
      self:write_out("Starting: " .. tostring(evt.name))
    elseif evt.type == "span_end" then
      self:write_out("Finished: " .. tostring(evt.name) .. " (" .. tostring(evt.status) .. ")")
    elseif evt.type == "milestone" then
      self:write_out("=> " .. tostring(evt.message))
    elseif evt.type == "progress" then
      -- Section 39: Plain does NOT emit tick spam (10%, 20%...)
      -- Only emit start or completion milestone
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
    -- Live terminal composition
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

---Section 40: Interactive prompt via Composer ownership.
---Non-interactive environments follow explicit deterministic policy.
function Composer:confirm(prompt, opts)
  opts = opts or {}
  local default_val = opts.default ~= nil and opts.default or false

  -- In json, quiet, or non-interactive mode, use deterministic default
  if self.mode == "json" or self.mode == "quiet" or not self.is_tty then
    return default_val
  end

  local hint = default_val and "[Y/n]" or "[y/N]"
  if self.out_sink then
    pcall(function()
      self.out_sink:write(prompt .. " " .. hint .. " ")
      self.out_sink:flush()
    end)
  end

  local line = io.read("*l")
  if not line or line == "" then
    return default_val
  end

  line = line:lower():match("^%s*(.-)%s*$")
  if line == "y" or line == "yes" then
    return true
  elseif line == "n" or line == "no" then
    return false
  end

  return default_val
end

M.Composer = Composer

function M.create_composer(opts)
  return Composer.new(opts)
end

return M
