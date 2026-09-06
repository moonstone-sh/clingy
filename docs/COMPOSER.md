# Clingy Composer (Default Presentation Host)

## 1. Overview

**Composer** is Clingy's default `PresentationHost` implementation. It provides terminal rendering, progress indicators, structured log formatting, prompt dialogues, and NDJSON streaming.

Composer is constructed via:

```lua
local comp = c.composer({
  mode = "auto",       -- "auto" | "fancy" | "plain" | "quiet" | "ndjson" (or "json")
  stdout = io.stdout,  -- Custom output stream sink
  stderr = io.stderr,  -- Custom error stream sink
  is_tty = nil,        -- Override TTY auto-detection (boolean)
  capture = false,     -- Buffer lines in comp.captured_lines for test assertions
})
```

---

## 2. Rendering Modes

### `auto` (Default)
Inspects the standard output sink:
- If `is_tty` is true (interactive terminal), activates **`fancy`** mode.
- If `is_tty` is false (piped or redirected to file), activates **`plain`** mode.

### `fancy`
Rich interactive terminal rendering:
- ANSI 256/Truecolor styling and semantic icons (`ℹ`, `✔`, `✖`, `⚠`).
- Live progress spinners and in-place progress percentage rendering (`\27[2K\r`).
- Milestone markers (`==> Deployment completed`).
- Span indentation and duration timing.

### `plain` (Semantic Reduction)
Designed for CI environments and log aggregators:
- **Zero ANSI escape sequences**: clean ASCII output.
- **Tick throttling**: filters repetitive progress ticks to prevent log flood (e.g. only emitting 0%, milestone jumps, or 100%).
- Prefix tags: `[INFO]`, `[WARN]`, `[ERROR]`, `=> Milestone`.

### `quiet`
Minimizes terminal noise:
- Suppresses informational logs (`ctx:log("info")`, `ctx:log("debug")`), progress indicators, and milestones.
- Emits only error logs, fatal diagnostics, and explicit command outputs (`ctx:result()`).

### `ndjson` (Machine Protocol)
Emits line-delimited JSON for machine ingestion:
- Each event is a single JSON line conforming to `clingy.events.v1`.
- Backwards-compatible with the legacy mode name `"json"`.

```json
{"protocol":"clingy.events.v1","type":"log","level":"info","message":"Connecting to server","sequence":1,"timestamp":1757134800}
{"protocol":"clingy.events.v1","type":"result","data":{"status":"ok"},"sequence":2,"timestamp":1757134801}
```

---

## 3. Terminal Handoff & Suspension

When an interactive subprocess is spawned, Composer suspends its terminal hooks:

```lua
function ComposerHost:suspend(reason)
  self.is_suspended = true
  if self.is_tty and self.mode == "fancy" then
    -- Flush pending line buffers and restore cursor
    self.stdout:write("\n")
    self.stdout:flush()
  end
end

function ComposerHost:resume()
  self.is_suspended = false
end
```

---

## 4. Prompts and Confirmation

Composer handles interactive prompts through `host:prompt(request)`:
- In interactive TTY mode, prints `request.prompt` and reads stdin (`io.read("*l")`).
- In non-interactive mode or when `is_tty == false`, falls back deterministically via `prompt.fallback(request)`.

---

## 5. Backward Compatibility

To ensure existing Clingy applications continue to run seamlessly:
1. `c.composer` is exported as a callable table (`__call` creates a composer, `new` creates a composer).
2. `app:run(argv, { composer = comp })` and `app:run(argv, { composer_mode = "plain" })` are fully supported.
3. `ctx.composer` is an alias to `ctx.presentation`.
