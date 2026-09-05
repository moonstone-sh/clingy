local util = require("clingy.util")

local M = {}

local EventEmitter = {}
EventEmitter.__index = EventEmitter

function EventEmitter.new(invocation_id)
  local self = setmetatable({}, EventEmitter)
  self.invocation_id = invocation_id or tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
  self.sequence = 0
  self.listeners = {}
  self.spans = {}
  self.current_span_id = nil
  return self
end

function EventEmitter:on(event_type, fn)
  if not self.listeners[event_type] then
    self.listeners[event_type] = {}
  end
  table.insert(self.listeners[event_type], fn)
end

function EventEmitter:on_any(fn)
  if not self.listeners["*"] then
    self.listeners["*"] = {}
  end
  table.insert(self.listeners["*"], fn)
end

---Emits a semantic event conforming to Section 36 attribution.
function EventEmitter:emit(event_type, data)
  self.sequence = self.sequence + 1
  data = data or {}

  local evt = {
    protocol = "clingy.events.v1",
    type = event_type,
    invocation_id = self.invocation_id,
    sequence = self.sequence,
    timestamp = os.time(),
    span_id = data.span_id or self.current_span_id,
    parent_span_id = data.parent_span_id,
    process_id = data.process_id,
  }

  for k, v in pairs(data) do
    if evt[k] == nil then
      evt[k] = v
    end
  end

  -- Dispatch to specific type listeners
  local specific = self.listeners[event_type]
  if specific then
    for _, fn in ipairs(specific) do
      pcall(fn, evt)
    end
  end

  -- Dispatch to wildcard listeners
  local all = self.listeners["*"]
  if all then
    for _, fn in ipairs(all) do
      pcall(fn, evt)
    end
  end

  return evt
end

function EventEmitter:start_span(name, parent_id)
  local span_id = "span-" .. tostring(self.sequence + 1)
  local span = {
    span_id = span_id,
    parent_span_id = parent_id or self.current_span_id,
    name = name,
    start_time = os.time(),
    ended = false,
  }
  self.spans[span_id] = span
  self.current_span_id = span_id
  self:emit("span_start", {
    span_id = span_id,
    parent_span_id = span.parent_span_id,
    name = name,
  })
  return span_id
end

function EventEmitter:end_span(span_id, status)
  local span = self.spans[span_id]
  if span and not span.ended then
    span.ended = true
    self:emit("span_end", {
      span_id = span_id,
      parent_span_id = span.parent_span_id,
      name = span.name,
      status = status or "ok",
      duration_ms = (os.time() - span.start_time) * 1000,
    })
    if self.current_span_id == span_id then
      self.current_span_id = span.parent_span_id
    end
  end
end

---Finalizes any unclosed spans during unwind (Section 24).
function EventEmitter:finalize_spans(status)
  for span_id, span in pairs(self.spans) do
    if not span.ended then
      span.ended = true
      self:emit("span_end", {
        span_id = span_id,
        parent_span_id = span.parent_span_id,
        name = span.name,
        status = status or "interrupted",
        duration_ms = (os.time() - span.start_time) * 1000,
      })
    end
  end
end

M.EventEmitter = EventEmitter

function M.create_bus(invocation_id)
  return EventEmitter.new(invocation_id)
end

return M
