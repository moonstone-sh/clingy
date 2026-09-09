# Clingy Presentation Host Boundary Compliance Report

## Executive Summary

The Clingy Presentation Host boundary has been extracted, hardened, verified, and audited. The Clingy runtime no longer assumes that the built-in Composer is the only representation layer. Composer is now the default `PresentationHost` implementation, fully decoupled from the core runtime lifecycle, command routing, and process supervision.

All **20 Foundational Invariants** (`HOST-INV-01` through `HOST-INV-20`) are verified, and all **30 Architecture Compliance Questions** in Part XXII are answered below.

```text
=========================================================
Test Results: 282 Passed, 0 Failed across 47 Test Suites
=========================================================
```

---

## Part I: Compliance Matrix for the 20 Invariants

| ID | Invariant Statement | Verification Proof |
|---|---|---|
| **HOST-INV-01** | Clingy runtime no longer assumes Composer is the only representation layer. | `App:run` mounts any `PresentationHost`; verified in `custom_host_spec.lua` and `scope_deferral_spec.lua`. |
| **HOST-INV-02** | Composer remains the polished default representation layer. | Calling `app:run()` without explicit presentation mounts Composer auto/fancy/plain/ndjson. |
| **HOST-INV-03** | Composer-specific options belong to Composer, not generic Host. | `opts.capture`, `is_tty`, `stdout`/`stderr` sinks belong to `c.composer(opts)` / `ComposerHost`. |
| **HOST-INV-04** | Custom Hosts consume canonical semantic events (`clingy.events.v1`). | Verified in `event_ingestion_spec.lua`; all events emit standard protocol payload. |
| **HOST-INV-05** | Runtime semantics do not depend on how events are rendered. | Handlers receive identical `ctx.args` and return values regardless of active host. |
| **HOST-INV-06** | Exactly one Presentation Host owns application presentation for an invocation. | Per-invocation `opts.presentation` strictly overrides config; verified in `scope_deferral_spec.lua`. |
| **HOST-INV-07** | Exactly one component owns terminal composition at a time. | Verified via single active host ownership, explicit host states, and child suspend/resume handoff. |
| **HOST-INV-08** | Hosts without terminal usage are valid (NullHost, machine hosts, recording hosts). | Verified in `test_hosts_spec.lua` (`NullHost`, `RecordingHost`, `FailingHost`). |
| **HOST-INV-09** | Interactive children can suspend and resume any terminal-owning Host (`mode = "interactive"`). | Verified in `subprocess_handoff_spec.lua`; if `suspend` fails, child execution is strictly aborted. |
| **HOST-INV-10** | Host acquisition and release use structured scopes (`scope:defer`). | Bound to `root_scope:defer` in `App:run`; verified in `scope_deferral_spec.lua`. |
| **HOST-INV-11** | Host release is exactly-once across normal return, runtime error, parse error, SIGINT, SIGTERM. | Verified in `scope_deferral_spec.lua` and `signals_handoff_spec.lua`. |
| **HOST-INV-12** | Presentation failure cannot leak terminal state or crash primary application logic. | Host methods wrapped in operation-specific severity containment; verified in `error_containment_spec.lua`. |
| **HOST-INV-13** | Signal policy stays in Clingy orchestrator. | Signals handled by `signals.dispatch` and `App:handle_signal`; verified in `signals_handoff_spec.lua`. |
| **HOST-INV-14** | A Host may represent prompts without becoming signal-policy authority. | `ctx:confirm` / `ctx:prompt` route to `host:prompt(request)` with structured prompt error propagation; verified in `prompt_protocol_spec.lua`. |
| **HOST-INV-15** | Captured process output is semantic event data (`process_output`). | Child subprocesses in capture mode emit `process_output` semantic events to the event bus. |
| **HOST-INV-16** | Inherited child output need not flow through Host. | `mode = "inherit"` subprocesses connect directly to OS stdio. |
| **HOST-INV-17** | TUI frameworks can mount without depending on Composer internals. | Custom stateful classes implement `PresentationHost` protocol cleanly; verified in `custom_host_spec.lua`. |
| **HOST-INV-18** | Clingy does not become a component/layout/reconciliation framework. | Host protocol is strictly an event/lifecycle boundary; UI frameworks manage their own trees. |
| **HOST-INV-19** | Existing fancy/plain/quiet/ndjson behavior remains supported. | Verified in `composer_host_spec.lua` and legacy `inv_20_21_composer_plain_spec.lua`. |
| **HOST-INV-20** | Simple Clingy apps still work without explicitly constructing a Host (`app:run()`). | Verified by the maintained runtime and presentation suites. |

---

## Part II: Answers to the 30 Architectural Questions

### 1. What is the single authoritative Presentation Host for an invocation?
The single authoritative host is resolved in `App:run` via `opts.presentation or opts.composer or self._config.presentation or default_composer`. Only this instance receives lifecycle calls and event stream subscriptions.

### 2. How does Clingy ensure Composer is not hardcoded in the core runtime?
All direct references to `composer` in `context.lua`, `process.lua`, and `signals.lua` were replaced with `ctx.presentation`. `App:run` treats `PresentationHost` as an abstract protocol. `ctx.composer` is maintained purely as a deprecated transitional alias.

### 3. What lifecycle methods make up the formal Presentation Host interface?
`start(invocation)`, `handle_event(event)`, `flush()`, `suspend(reason)`, `resume()`, `prompt(request)`, `finish(result)`, and `close()`.

### 4. When is `host:start()` invoked relative to argument parsing?
`host:start()` is called **before** `parser.parse()`. If `host:start()` fails, it is treated as a fatal presentation initialization error, aborting execution immediately with exit code 1.

### 5. When is `host:finish()` invoked relative to handler completion and errors?
`host:finish()` is invoked during the `finalize` stage of the Lifecycle DAG, reporting `{ status = "ok"|"failed", exit_code = ... }` before `host:close()` executes during scope unwind.

### 6. When is `host:close()` invoked and what guarantees its execution?
`host:close()` is registered in `root_scope:defer()` during `App:run`. Structured scope unwinding guarantees exactly-once execution across normal exit, errors, and signal aborts.

### 7. How does Clingy differentiate Host failure severity?
- `start`: Fatal presentation initialization error (aborts invocation).
- `handle_event`: Containable (safe `pcall` ensures nonessential rendering issues do not crash business logic).
- `prompt`: Structured prompt failure (propagates error).
- `suspend`: Strict gate (aborts interactive subprocess execution if suspension fails).
- `resume`: Infrastructure failure (emits error diagnostic).
- `finish`: Recorded presentation failure (preserves primary domain result).
- `close`: Cleanup error (aggregated in scope unwind).

### 8. How does Clingy prevent terminal corruption during interactive subprocess execution?
In `ManagedProcess:wait()` (`mode = "interactive"`), Clingy calls `host:suspend({ reason = "subprocess", process = self })`. If `suspend()` fails, Clingy **strictly aborts** and never executes `os.execute()`. Upon child exit, `host:resume()` is called in a protected block.

### 9. What happens if an interactive subprocess crashes or receives SIGKILL?
`host:resume()` is called in a protected cleanup block in `ManagedProcess:wait()`, ensuring the presentation host is always resumed regardless of how the child terminates.

### 10. How is non-interactive prompt fallback handled for `confirm`?
If `request.default` is specified, it returns `request.default`; otherwise, it returns `false`.

### 11. How is non-interactive prompt fallback handled for `text` prompts?
If `request.default` is specified, it returns `request.default`; if no default is provided, it raises a clean, descriptive error: `"Cannot prompt for text in non-interactive mode without a default value"`.

### 12. How does `ctx:confirm` delegate to the active Presentation Host?
`ctx:confirm(prompt, opts)` wraps the arguments into `{ type = "confirm", prompt = prompt, default = opts.default, timeout_ms = opts.timeout_ms }` and calls `ctx.presentation:prompt(request)`.

### 13. How does `ctx:prompt` work for general prompt types?
`ctx:prompt(request)` forwards the structured request table directly to `ctx.presentation:prompt(request)` and propagates any structured prompt failures.

### 14. What modes does the default Composer support?
`auto` (TTY-sensing), `fancy` (rich ANSI/spinners), `plain` (semantic reduction/zero ANSI), `quiet` (errors and results only), and `ndjson` (line-delimited machine protocol).

### 15. Is `"json"` mode still supported?
Yes, `"json"` is fully supported as a backward-compatible alias for `"ndjson"`.

### 16. What is the semantic reduction implemented in Composer `plain` mode?
Plain mode disables all ANSI escape codes, strips spinner frames, and throttles progress updates to milestone boundaries and endpoints (0% / 100%), preventing CI log spam.

### 17. How does Composer `quiet` mode behave?
Suppresses `debug` and `info` logs, progress updates, and milestones. Only `warn`, `error`, `diagnostic`, and explicit `result` outputs are emitted.

### 18. Where does `NullHost` fit in the ecosystem?
`NullHost` provides a completely silent no-op implementation of `PresentationHost` for headless execution, automated batch pipelines, and zero-overhead performance testing.

### 19. What capabilities does `RecordingHost` provide for test authors?
Captures all `events`, `calls`, and `prompts` in sequential tables, and supports scripted `prompt_responses` (array or function) for automated interactive CLI testing.

### 20. What is `FailingHost` used for?
`FailingHost` provides configurable fault injection (`fail_on = { method = "..." }`) to verify runtime resilience when presentation hosts fail.

### 21. How can a developer mount a custom TUI framework as a Host?
By implementing `handle_event`, `start`, `suspend`, `resume`, and `close`, and passing the instance to `c.create({ presentation = my_tui })` or `app:run(argv, { presentation = my_tui })`.

### 22. Can a minimal Lua table act as a Presentation Host?
Yes. Any table implementing `handle_event(self, event)` is a valid Presentation Host. Missing lifecycle methods (`start`, `flush`, `suspend`, `resume`, `finish`, `close`) are handled safely as no-ops.

### 23. How are shell completion requests handled relative to the Presentation Host?
Hidden completion queries (`--__clingy-complete`) intercept execution before host mounting and event bus emission, writing raw candidates directly to `opts.stdout` with zero presentation overhead.

### 24. Does the Presentation Host own signal policy?
No. Signal normalization, policy resolution, and dispatch remain strictly owned by Clingy's `signals.lua` and `App:handle_signal`.

### 25. How do signals coordinate with prompt cancellation?
If an interrupt signal is received during an active prompt, the prompt returns `false` or its non-interactive fallback and allows the signal policy to take action.

### 26. Are `process_output` events captured and delivered to the Host?
Yes. When a managed process is spawned in `capture` mode, its stdout and stderr streams are emitted as `process_output` semantic events to the event bus and received by `host:handle_event()`.

### 27. How does backward compatibility for `opts.composer` and `opts.composer_mode` work?
`App:run` checks `opts.presentation or opts.composer`. Both `opts.composer` and `opts.composer_mode` are marked as deprecated compatibility options.

### 28. Is `ctx.composer` still accessible in command handlers?
Yes, `ctx.composer` is maintained as a deprecated compatibility alias to `ctx.presentation`, scheduled for removal at the next major breaking boundary.

### 29. What is the latency overhead of the Presentation Host boundary?
Microbenchmarks show that 1,000 events take **2.40 ms total (2.40 µs / event)** through the host boundary, and invocation latency is **~0.03 ms**, introducing zero perceptible overhead.

### 30. How are LuaLS types provided for the Presentation Host subsystem?
`luals/library/clingy.lua` declares `---@class clingy.PresentationHost`, `---@class clingy.ComposerOptions`, `c.presentation`, `c.composer`, `c.null_host`, `c.recording_host`, and `c.failing_host`.

---

## Part III: Benchmark Results

```text
[Perf Benchmark] Host boundary 1,000 events: 2.40 ms total (2.40 µs / event)
[Perf Benchmark] Avg Invocation Latency (N=100):
  - NullHost:      0.037 ms
  - RecordingHost: 0.044 ms
  - ComposerHost:  0.031 ms
```
