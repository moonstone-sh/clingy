# Clingy Presentation Host Boundary & Composer Audit

## Audit Overview

This document analyzes the historical coupling between the Clingy CLI runtime and the built-in Composer, and records the architectural audit findings prior to extracting the formal Presentation Host boundary.

---

## Part I: Audit Questions & Detailed Findings

### 1. Who currently instantiates Composer?
- **Prior State**: In `src/clingy/app.lua`, `App:run` called `composer_mod.create_composer(opts)` directly during the invocation bootstrap. There was no seam for an external host to take ownership of presentation.
- **Refactored Boundary**: `App:run` resolves presentation through `opts.presentation or opts.composer or self._config.presentation`. If none is provided, it instantiates the default Composer via `clingy.presentation.composer.create_composer(opts)`.

### 2. Which modules call Composer directly?
- **Prior State**:
  - `src/clingy/context.lua` stored `ctx.composer` and delegated `ctx:confirm()` directly to `composer:prompt()`.
  - `src/clingy/process.lua` accessed `ctx.composer:suspend()` / `ctx.composer:resume()` during interactive subprocess execution.
  - `src/clingy/signals.lua` coordinated prompt cancellation with `ctx.composer`.
- **Refactored Boundary**:
  - `Context` stores `ctx.presentation` (with `ctx.composer` preserved as a backward-compatible alias).
  - `Process` interacts strictly with `ctx.presentation:suspend()` and `ctx.presentation:resume()`.
  - `Context:confirm()` and `Context:prompt()` route through `ctx.presentation:prompt(request)`.

### 3. Which modules emit semantic events?
- **Architecture**:
  - `src/clingy/context.lua`: Emits `log`, `progress`, `milestone`, `result`, `span_start`, `span_end`, and `diagnostic`.
  - `src/clingy/app.lua`: Emits `invocation_start`, `invocation_finish`, and parse-time `diagnostic`.
  - `src/clingy/process.lua`: Emits `process_output` (in capture mode).
  - All events flow through the canonical `clingy.events.v1` schema on `EventBus`.

### 4. Which runtime paths bypass events and write directly?
- **Findings**:
  - `--__clingy-complete`: Shell completion bypasses all presentation hosts and event streams, writing shell-specific completion shims/candidates directly to the designated `stdout` stream (`opts.stdout` or `io.stdout`). This guarantees zero latency overhead and zero escape code pollution for shell completion.
  - Interactive subprocesses (`mode = "interactive"`): When suspended, the child process attaches directly to standard OS file descriptors (`/dev/tty` / stdio).
  - All other runtime output strictly flows through `clingy.events.v1` events to `PresentationHost:handle_event()`.

### 5. Which parts of Composer own terminal state?
- **Findings**:
  - ANSI escape codes, cursor repositioning (`\27[2K\r`), and spin loop rendering in `fancy` mode.
  - Plain mode text formatting (zero ANSI, semantic reduction).
  - Stream redirection (`stdout` and `stderr` sinks).
  - Interactive prompt line reading (`io.read("*l")`) and prompt hints (`[Y/n]`).

### 6. How are interactive children currently suspended/resumed?
- **Prior State**: `ManagedProcess:wait()` checked `self.mode == "interactive"` and called `ctx.composer:suspend()` before spawning and `ctx.composer:resume()` after process exit.
- **Refactored Boundary**: `ManagedProcess:wait()` queries `ctx.presentation`. If `ctx.presentation.suspend` is present, it invokes `ctx.presentation:suspend("interactive_child")` before `os.execute()` and invokes `ctx.presentation:resume()` inside a protected cleanup block (`pcall`) upon process exit.

### 7. Does JSON mode live inside Composer or elsewhere?
- **Findings**:
  - JSON (NDJSON) rendering is implemented as a mode (`mode = "ndjson"`, with `"json"` alias) of `ComposerHost`.
  - Each canonical semantic event is serialized to an NDJSON line containing `{"protocol":"clingy.events.v1", ...}` and written to the output sink.
  - Custom machine hosts can also receive raw event tables directly via `host:handle_event(evt)` without string serialization overhead.

### 8. Does prompt handling depend directly on Composer?
- **Prior State**: Prompt logic was implemented inside `src/clingy/composer.lua`.
- **Refactored Boundary**: Prompting is decoupled into `src/clingy/presentation/prompt.lua`. Hosts implement `host:prompt(request)`. Non-interactive hosts (such as `NullHost`, `ndjson` mode, or non-TTY plain mode) utilize `prompt.fallback(request)` for deterministic evaluation.

### 9. Which assumptions prevent replacing Composer today?
- **Prior Assumptions Eliminated**:
  1. Assumption that `ctx.composer` is a concrete Composer class instance. -> **Replaced by `PresentationHost` protocol**.
  2. Hardcoded calls to Composer methods during subprocess handoff. -> **Generalized to `host:suspend()` / `host:resume()`**.
  3. Direct coupling of prompt handling to Composer terminal rendering. -> **Decoupled to `host:prompt(request)` with non-interactive fallbacks**.
  4. Coupling of JSON output to Composer mode. -> **Custom machine hosts can be mounted directly**.

---

## Part II: Key Architectural Recommendations

1. **Early Host Mounting (`start` before parse)**:
   Calling `host:start()` prior to argument parsing ensures that command syntax errors and schema validation diagnostics are reported through the active Presentation Host rather than bypassing it.
2. **Protected Execution (`pcall` containment)**:
   Wrapping host lifecycle methods (`start`, `handle_event`, `finish`, `close`) in safe execution wrappers guarantees that custom host rendering failures never terminate the primary application or mask domain exit codes.
3. **Structured Scope Integration**:
   Registering `host:close()` inside the root `Scope:defer` ensures exactly-once resource release across normal exit, errors, and signal unwinds.
