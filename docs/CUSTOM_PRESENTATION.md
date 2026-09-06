# Authoring Custom Presentation Hosts

## 1. Overview

Clingy's **Presentation Host** boundary allows developers to attach custom user interfaces, TUI engines, IDE language server bridges, remote web dashboards, or testing harnesses without modifying Clingy's core parser, router, or subprocess supervisors.

---

## 2. Minimal Presentation Host

Any table with a `handle_event(self, event)` method can act as a valid Presentation Host:

```lua
local MinimalHost = {}

function MinimalHost:handle_event(event)
  if event.type == "log" then
    print(string.format("[%s] %s", event.level:upper(), event.message))
  elseif event.type == "result" then
    print("OUTPUT: " .. tostring(event.data))
  end
end

-- Mount in App
local app = c.create({
  name = "demo-app",
  presentation = MinimalHost,
  c.root(c.node({
    c.run(function(ctx)
      ctx:log("info", "Running with minimal host")
      return { success = true }
    end),
  })),
})

app:run({})
```

---

## 3. Full Stateful Presentation Host (TUI / Dashboard)

For complex graphical or terminal UI applications, inherit from `clingy.presentation.PresentationHost`:

```lua
local c = require("clingy")
local host_mod = require("clingy.presentation.host")

local TuiHost = setmetatable({}, { __index = host_mod.PresentationHost })
TuiHost.__index = TuiHost

function TuiHost.new(opts)
  local self = setmetatable({}, TuiHost)
  self.spans = {}
  self.logs = {}
  self.is_running = false
  return self
end

function TuiHost:start(invocation)
  self.is_running = true
  self.app_name = invocation.app_name
  self.invocation_id = invocation.invocation_id
  -- Initialize TUI screen buffer / raw mode
end

function TuiHost:handle_event(event)
  if event.type == "span_start" then
    self.spans[event.span_id] = { name = event.name, start = event.timestamp }
  elseif event.type == "span_end" then
    self.spans[event.span_id] = nil
  elseif event.type == "log" then
    table.insert(self.logs, { level = event.level, msg = event.message })
  end
  self:render_frame()
end

function TuiHost:suspend(reason)
  -- Leave TUI alternate screen buffer and restore terminal cooked mode
end

function TuiHost:resume()
  -- Re-enter TUI alternate screen buffer and redraw active UI state
  self:render_frame()
end

function TuiHost:prompt(request)
  -- Show interactive modal dialog in TUI and return response
  return request.default
end

function TuiHost:finish(result)
  self.is_running = false
  self.final_result = result
end

function TuiHost:close()
  -- Teardown TUI curses/raw mode and release screen resources
end

function TuiHost:render_frame()
  -- Draw dashboard widgets to terminal
end

return TuiHost
```

---

## 4. Mounting Presentation Hosts

Hosts can be mounted at application construction time or overridden per invocation:

### Option A: App Construction
```lua
local my_host = TuiHost.new()
local app = c.create({
  name = "my-service",
  presentation = my_host,
  c.root(...),
})
```

### Option B: Per-Invocation Override
```lua
local test_host = c.recording_host()
local exit_code = app:run(argv, { presentation = test_host })
```

---

## 5. Best Practices

1. **Non-blocking `handle_event`**: Process events quickly to avoid stalling the CLI execution flow.
2. **Defensive Resource Cleanup**: Ensure `close()` releases all opened terminal buffers, sockets, or file handles. Clingy guarantees `close()` will be called exactly once upon scope unwind.
3. **Graceful Subprocess Suspension**: Always restore normal terminal modes in `suspend()` so child processes (`ctx:spawn({ mode = "interactive" })`) have full, unhindered terminal access.
