# Clingy Presentation Host Architecture

## 1. Overview

Clingy separates runtime execution, lifecycle orchestration, and process supervision from presentation rendering.

The **Presentation Host Boundary** defines the formal contract between Clingy and whatever component owns terminal display, TUI state, IDE RPC channels, or telemetry logging.

```text
Clingy Runtime
    │
    ├── router & argument parser
    ├── lifecycle DAG & scopes
    ├── subprocesses & signals
    └── canonical semantic events (clingy.events.v1)
             │
             ▼
      Presentation Host (single active instance)
             │
      ┌──────┴──────────────┬──────────────────┐
      ▼                     ▼                  ▼
Default Composer       Custom Host         Test Hosts
  ├── auto               ├── TUI             ├── NullHost
  ├── fancy              ├── Dashboard       ├── RecordingHost
  ├── plain              ├── IDE Bridge      └── FailingHost
  ├── quiet              └── Remote UI
  └── ndjson
```

---

## 2. Canonical vs. Transitional Vocabulary

To avoid leaky abstractions and ensure rapid ecosystem convergence:

| Surface | Canonical & Stable | Deprecated Compatibility Alias |
|---|---|---|
| **Context** | `ctx.presentation` | `ctx.composer` *(transitional; to be removed at next major boundary)* |
| **Invocation Opts** | `app:run(argv, { presentation = h })` | `opts.composer`, `opts.composer_mode` |
| **App Config** | `c.create({ presentation = h })` | — |

---

## 3. The Presentation Host Protocol

A Presentation Host implements up to 8 lifecycle methods:

```lua
---@class clingy.PresentationHost
local PresentationHost = {}

---Called once during invocation bootstrap prior to argument parsing.
---Failure in start() is a FATAL presentation initialization error.
---@param invocation { invocation_id: string, app_name: string, version?: string, argv: string[] }
function PresentationHost:start(invocation) end

---Receives canonical semantic events conforming to clingy.events.v1.
---@param event table Conforming to clingy.events.v1
function PresentationHost:handle_event(event) end

---Requests that any buffered display output be flushed immediately.
function PresentationHost:flush() end

---Suspends presentation rendering (e.g. before launching an interactive child process).
---MUST succeed before interactive subprocess execution; failure strictly aborts spawn.
---@param reason? string|table e.g. { reason = "subprocess", process = proc }
function PresentationHost:suspend(reason) end

---Resumes presentation rendering after suspension.
function PresentationHost:resume() end

---Prompts user for input or confirmation.
---@param request { type?: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }
---@return any
function PresentationHost:prompt(request) end

---Called when the invocation completes with its final exit status.
---@param result { status: "ok"|"failed"|"interrupted"|"terminated", exit_code: integer, error?: any }
function PresentationHost:finish(result) end

---Closes the host and releases all allocated resources (terminal raw mode, open sockets, sinks).
---Guaranteed to execute exactly once via structured scope deferral.
function PresentationHost:close() end
```

---

## 4. Operation-Specific Failure Severity

Rather than treating all host failures identically, Clingy differentiates failure severity by lifecycle operation:

| Operation | Severity | Runtime Policy |
|---|---|---|
| **`start`** | **Fatal Initialization Error** | Aborts invocation immediately with `exit_code = 1`; emits diagnostic and unwinds scope. |
| **`handle_event`** | **Containable** | Protected by `pcall`; failures in nonessential rendering do not crash application logic. |
| **`prompt`** | **Structured Prompt Failure** | Errors in `host:prompt` propagate to the caller as structured execution failures. |
| **`suspend`** | **Strict Subprocess Gate** | **MUST abort interactive child execution**. If `suspend` fails, `os.execute` is never run. |
| **`resume`** | **Infrastructure Failure** | Protected by `pcall`; emits error diagnostic to warn of emergency restoration failure. |
| **`finish`** | **Presentation Failure** | Recorded; primary domain invocation result and exit code are preserved. |
| **`close`** | **Cleanup Error** | Executed in `scope:defer`; cleanup failures are caught and aggregated. |

---

## 5. Explicit Host State Machine

`PresentationHost` enforces an explicit internal lifecycle state machine:

```text
       [created]
           │
           │ start()
           ▼
       [started]
           │
           │ handle_event() / run
           ▼
       [active] ◄───────┐
           │            │
 suspend() │            │ resume()
           ▼            │
      [suspended] ──────┘
           │
           │ finish()
           ▼
       [finished]
           │
           │ close()
           ▼
        [closed]
```

### Transition Invariants
1. `host:resume()` is rejected unless the host is currently in state `suspended`.
2. `host:suspend()` is rejected if the host is in state `created`, `suspended`, or `closed`.
3. `host:handle_event()` is rejected if the host is in state `closed`.
4. `host:close()` is safe and idempotent (guards against duplicate closure).

---

## 6. Subprocess Terminal Handoff

When a managed subprocess is spawned in `interactive` mode, Clingy strictly enforces terminal handoff:

```lua
-- In ManagedProcess:wait() for mode == "interactive"
if host and host.suspend then
  local ok_suspend, err = pcall(host.suspend, host, { reason = "subprocess", process = self })
  if not ok_suspend then
    self.exit_code = 1
    self:set_state("killed")
    error("Failed to suspend Presentation Host before interactive subprocess: " .. tostring(err))
  end
end

local ok, exit_type, code = pcall(os.execute, cmd_str)

if host and host.resume then
  local ok_resume, resume_err = pcall(host.resume, host)
  if not ok_resume then
    bus:emit("diagnostic", { type = "diagnostic", message = "Host failed to resume: " .. tostring(resume_err), level = "error" })
  end
end
```

**Core Invariant:** If `host:suspend()` fails, Clingy never spawns the child process, preventing split-brain terminal conflicts between a full-screen TUI and a child process.

---

## 7. Built-in Test Hosts

- `c.null_host()`: Silent discard host for headless performance testing and batch pipelines.
- `c.recording_host(opts)`: Captures all `events`, `calls`, and `prompts`, with scripted `prompt_responses`.
- `c.failing_host(opts)`: Injects configurable faults (`fail_on = { start = "...", suspend = "..." }`) for resilience testing.
