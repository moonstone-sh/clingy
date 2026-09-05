# Clingy Process Ownership, Supervision, and Signal Semantics (`docs/PROCESSES_AND_SIGNALS.md`)

## 1. Process Supervision & State Machine

Clingy provides structured subprocess management through `ManagedProcess` handles (`ctx:spawn` or `scope:spawn`).

### 1.1 Process Lifecycle States

Managed processes transition through explicit states:

```text
┌───────────┐
│ declared  │  Process configuration defined with argv, env, cwd, mode
└─────┬─────┘
      ▼
┌───────────┐
│ spawning  │  Process initialization started; PID assigned
└─────┬─────┘
      ▼
┌───────────┐
│  running  │  Subprocess actively executing
└─────┬─────┘
      ├────────────────────────────┬─────────────────────────────┐
      │ (graceful shutdown)        │ (kill / timeout)            │ (normal completion)
      ▼                            ▼                             ▼
┌───────────┐                ┌───────────┐                 ┌───────────┐
│ draining  │                │  killed   │                 │  reaped   │
└─────┬─────┘                └─────┬─────┘                 └───────────┘
      ▼                            ▼                             ▲
┌─────────────┐                    │                             │
│ terminating │────────────────────┴─────────────────────────────┘
└─────────────┘
```

### 1.2 Mandatory Process Ownership Invariant (Section 13)
> **If Clingy owns a process, Clingy retains ownership until the process is reaped or explicitly detached.**
No process may disappear from supervision after kill or requested termination. Scopes closing while a managed process is running automatically trigger termination and wait for reaping during scope unwind.

---

## 2. Process I/O Ownership & Modes

Clingy supports 4 explicit I/O modes:

| Mode | Behavior | Terminal / Stream Handling |
|---|---|---|
| `capture` | Subprocess output is buffered; emitted as `process_output` events over the event bus | Composer receives structured output; stdout/stderr buffers accessible on process handle |
| `inherit` | Subprocess inherits parent standard I/O streams | Raw pass-through to terminal streams |
| `interactive` | Terminal ownership is temporarily suspended by Composer and yielded to child | Composer suspends live redraws, child runs interactively, Composer resumes upon child exit |
| `protocol` | Dedicated bidirectional control IPC channel for structured message exchange | Control IPC is isolated from stdout/stderr; emits `process_ipc_send` semantic events |

---

## 3. Signal Semantics & Identity Preservation

Clingy preserves distinct normalized identities for operating system signals:
- `SIGINT` (2) $\to$ `"interrupt"`
- `SIGTERM` (15) $\to$ `"terminate"`
- `SIGHUP` (1) $\to$ `"hangup"`

### 3.1 Policy Precedence
Signal policies declared via `c.signals({ ... })` are resolved hierarchically:
1. **Nearest Active Scope**: Handlers declared on the active leaf segment are consulted first.
2. **Ancestor Commands**: If unhandled, ancestor segments are checked in reverse route order.
3. **Application Default**:
   - `interrupt` $\to$ prompts interactive confirmation (if TTY) or initiates graceful drain.
   - `terminate` $\to$ initiates immediate shutdown.

---

## 4. Shutdown Escalation Model (Section 19)

Clingy implements an explicit escalation state machine:

```text
running
   ↓
shutdown_requested
   ↓
draining (grace period timeout)
   ↓
terminating (SIGTERM sent to children)
   ↓
force_kill (SIGKILL sent if grace expires)
   ↓
reap (all exit codes recorded)
   ↓
finalize (scopes unwound, terminal restored)
```

### 4.1 Key Escalation Rules:
1. **Repetitive `SIGINT` (Second Ctrl+C)**: If a second `SIGINT` arrives while graceful shutdown is in progress, Clingy immediately escalates to `force_shutdown`.
2. **`SIGTERM` during Interactive Confirmation (Section 20)**: If `SIGTERM` arrives while the user is being prompted to confirm a `SIGINT` abort, Clingy immediately cancels the prompt and forces shutdown without waiting for user input.
