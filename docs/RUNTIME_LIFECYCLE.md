# Clingy Runtime Lifecycle & Structured Scopes (`docs/RUNTIME_LIFECYCLE.md`)

## 1. Abstract

Clingy models the execution of a CLI invocation as a deterministic, topologically ordered **Invocation Lifecycle DAG**, coupled with hierarchical **Structured Scopes** providing strictly ordered LIFO resource cleanup.

This architecture ensures that:
1. Lifecycle stages execute in a deterministic dependency order.
2. Resource allocation (processes, file descriptors, network connections) is tied to explicit scope boundaries.
3. Cleanup is guaranteed across all exit paths: normal return, runtime error, signal interruption (`SIGINT`), and termination (`SIGTERM`).

---

## 2. Invocation Lifecycle DAG

The lifecycle DAG orchestrates the phases of a CLI invocation.

```text
┌─────────────┐
│  bootstrap  │  Initialize invocation context, allocate monotonic event bus
└──────┬──────┘
       ▼
┌─────────────────┐
│ terminal_detect │  Inspect environment (TTY, CI, TERM) to determine presentation mode
└──────┬──────────┘
       ▼
┌───────────┐
│   parse   │  Parse argv against Compiled Router; resolve route and arguments
└──────┬────┘
       ▼
┌───────────┐
│   route   │  Match segment path and assign argument ownership
└──────┬────┘
       ▼
┌────────────┐
│  validate  │  Execute Valua Standard Schema semantic validation
└──────┬─────┘
       ▼
┌───────────┐
│  prepare  │  Prepare execution scope and pre-run hooks
└──────┬────┘
       ▼
┌───────────┐
│  dispatch │  Dispatch signal policies and attach process supervisor
└──────┬────┘
       ▼
┌─────────┐
│   run   │  Execute application command handler `c.run(function(ctx) ... end)`
└──────┬──┘
       ▼
┌──────────┐
│ finalize │  Unwind scopes, reap child processes, emit final event and exit code
└──────────┘
```

### 2.1 Stage Customization & Cycle Detection
Custom stages may be declared on nodes using `c.stage({ id = "custom_step", before = {...}, after = {...} })`.
- Stage dependencies are resolved via topological sort.
- Dependency cycles raise an immediate compile/init error (`"Lifecycle DAG error: Cycle detected involving stage '...'"`).

---

## 3. Structured Scopes & Resource Deferral

Clingy provides structured lexical scopes via `ctx:scope(function(scope) ... end)` and `scope:scope(...)`.

### 3.1 Cleanup Registration (`scope:defer`)
Callbacks registered with `scope:defer(fn)` are pushed onto a LIFO cleanup stack:

```lua
ctx:scope(function(scope)
  local tmp_file = io.open("/tmp/payload.dat", "w")
  scope:defer(function()
    tmp_file:close()
    os.remove("/tmp/payload.dat")
  end)

  -- If an error occurs here, deferred cleanup is guaranteed to execute
  process_file(tmp_file)
end)
```

### 3.2 Unwind Guarantees
1. **Inner-First Unwinding**: Nested child scopes unwind completely before parent scope deferrals execute.
2. **Strict LIFO Order**: Deferrals within a scope execute in reverse registration order.
3. **Multi-Error Aggregation (Section 11)**:
   If a handler fails with error `E1`, and one or more cleanup callbacks fail with errors `E2`, `E3`:
   - Clingy executes *all* remaining cleanup callbacks to completion.
   - The primary error `E1` is preserved as `ctx._error`.
   - All cleanup errors `{ E2, E3 }` are aggregated in `ctx._cleanup_errors`.
   - Machine event streams emit both the primary failure and the cleanup error list.

---

## 4. Lifecycle Error & Exit Status Categories

Clingy distinguishes 7 distinct result categories:

| Category | Description | Exit Code |
|---|---|---|
| `success` | Successful execution of all lifecycle stages and handler | `0` |
| `usage_error` | Lexical grammar violation, unknown option, misplaced option, missing argument | `1` |
| `validation_error` | Semantic validation failure via Valua Standard Schema | `1` |
| `application_error` | Unhandled Lua exception or `ctx:fail(msg, code)` in command handler | User code (default `1`) |
| `infrastructure_error` | Lifecycle DAG dependency cycle, process supervisor failure | `2` |
| `interrupt` | Graceful termination triggered by `SIGINT` (Ctrl+C) | `130` |
| `termination` | Immediate or forced shutdown triggered by `SIGTERM` / second `SIGINT` | `143` |
