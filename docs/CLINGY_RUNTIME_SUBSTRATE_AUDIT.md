# Clingy Runtime Substrate Audit (`docs/CLINGY_RUNTIME_SUBSTRATE_AUDIT.md`)

## 1. Executive Summary

This document reports the structural audit of Clingy's lower runtime substrate: the **Invocation Lifecycle DAG**, **Structured Scopes**, **Process Supervision**, **Signal Dispatch**, and **Terminal Composer**.

---

## 2. Invocation Lifecycle DAG Audit

### 2.1 Canonical Lifecycle Stages
The default lifecycle graph consists of 9 deterministic stages:
```text
bootstrap -> terminal_detect -> parse -> route -> validate -> prepare -> dispatch -> run -> finalize
```

### 2.2 Extension, Topological Ordering, & Cycle Detection
- Custom stages can be inserted by declaring `c.stage({ id = "custom", after = {"validate"}, before = {"run"} })`.
- Dependencies are sorted topologically using Tarjan's cycle-detection algorithm. Cycles fail immediately during app compilation.
- **Workload DAG Separation**: The Lifecycle DAG manages the execution phases of the CLI engine itself; it does not model application workload DAGs, build targets, or artifact caching (which remain the exclusive responsibility of Ballad).

---

## 3. Structured Scopes & Deterministic Unwind Audit

### 3.1 Scope Hierarchy & Deferral Storage
- Each scope (`Scope.new(parent, ctx)`) maintains a LIFO array `self.defers` of cleanup callbacks.
- Scope trees unwind depth-first: all child scopes unwind completely before parent scope deferrals execute.

### 3.2 Error Semantics & Multi-Failure Aggregation
- If a handler throws error `E1`, and multiple deferred cleanups throw errors `E2` and `E3`:
  - Clingy preserves `primary = E1` and aggregates all cleanup errors into `cleanup_errors = { E2, E3 }`.
  - No cleanup callback is skipped if a preceding cleanup callback throws an error.

---

## 4. Process Supervision & Ownership Audit

### 4.1 Explicit State Machine
Managed processes transition through 7 explicit states:
`declared` $\to$ `spawning` $\to$ `running` $\to$ `draining` $\to$ `terminating` $\to$ `killed` $\to$ `reaped`.

### 4.2 Ownership Invariant
- A managed process is owned by the enclosing `Scope`.
- If the scope closes while the process is running, the scope unwind handler automatically terminates and waits for the process to be reaped.
- A process handle is never released until its termination status and exit code have been captured.

---

## 5. Signal Dispatch & Shutdown Escalation Audit

### 5.1 Signal Normalization & Backend Separation
- Operating system signals are captured by the backend and normalized into semantic signal events (`interrupt`, `terminate`, `hangup`).
- Arbitrary application Lua callbacks are never invoked inside unsafe OS signal interrupts.

### 5.2 Shutdown Escalation Rules
- **Second `SIGINT`**: Escalates immediately from graceful drain to `force_shutdown`.
- **`SIGTERM` during Interactive Prompt**: If a termination signal arrives while waiting for user confirmation on a `SIGINT` abort prompt, the interactive prompt is cancelled immediately and shutdown proceeds unconditionally.

---

## 6. Terminal Composer & Event Protocol Audit

### 6.1 Single Ownership
- Exactly one `Composer` instance owns terminal output and ANSI cursor states.
- Interactive child processes cause the Composer to suspend live redraws, yield terminal control, and resume upon child completion.

### 6.2 Machine NDJSON Protocol
- JSON mode emits strictly monotonic NDJSON envelopes conforming to `clingy.events.v1`.
- All unclosed spans are finalized during invocation unwind.
