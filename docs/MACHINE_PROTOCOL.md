# Clingy Machine Event Protocol Specification (`clingy.events.v1`)

## 1. Abstract & Scope

This document specifies the normative NDJSON event protocol version `clingy.events.v1` emitted by Clingy applications in machine mode (`--json` or `mode = "json"`).

Every event emitted over the stream represents a semantic lifecycle milestone, telemetry point, or operational action.

---

## 2. Protocol Envelope

Every emitted line is a standalone JSON object adhering to this schema:

```json
{
  "protocol": "clingy.events.v1",
  "invocation_id": "1725548000-8492",
  "sequence": 42,
  "timestamp": 1725548001,
  "type": "progress",
  "span_id": "span-3",
  "parent_span_id": "span-1",
  "process_id": null,
  "task": "compile",
  "percentage": 85,
  "message": "Linking objects"
}
```

### Standard Fields:
- **`protocol`** `string`: Always `"clingy.events.v1"`.
- **`invocation_id`** `string`: Unique identifier for the CLI execution.
- **`sequence`** `integer`: **Strictly monotonic** counter per invocation ($1, 2, 3, \dots$).
- **`timestamp`** `integer`: Unix epoch timestamp in seconds.
- **`type`** `string`: Discriminator indicating the semantic event payload.
- **`span_id`** `string?`: Identifier of the active enclosing span.
- **`parent_span_id`** `string?`: Identifier of the parent span (for nested spans).
- **`process_id`** `string?`: Identifier of the associated managed subprocess (if applicable).

---

## 3. Supported Event Types & Payloads

| Event Type | Description | Key Payload Fields |
|---|---|---|
| `invocation_start` | Emitted when CLI lifecycle starts | `app_name`, `version`, `target_command` |
| `invocation_finish` | Emitted when CLI lifecycle concludes | `exit_code`, `status` (`"ok"` or `"failed"`) |
| `span_start` | Beginning of a measured operational span | `name` |
| `span_end` | Completion of a measured span | `name`, `status`, `duration_ms` |
| `progress` | Progress update on a long-running task | `task`, `percentage`, `message` |
| `milestone` | High-level semantic achievement | `message` |
| `log` | Operational log entry | `level` (`"debug"`, `"info"`, `"warn"`, `"error"`, `"fatal"`), `message` |
| `diagnostic` | Parse, validation, or CLI usage error | `message`, `exit_code`, `path` |
| `result` | Final command payload output | `data` / `message` |
| `process_start` | Managed subprocess spawned | `argv`, `mode` |
| `process_output` | Subprocess output chunk captured | `stream` (`"stdout"` or `"stderr"`), `data` |
| `process_exit` | Managed subprocess reaped | `exit_code` |
| `process_ipc_send` | Control IPC message sent | `message` |
| `signal` | Normalized OS signal dispatched | `raw_signal`, `signal`, `count` |

---

## 4. Guarantees & Compatibility Rules

1. **No Mixed Output**: Zero non-JSON text, ANSI sequences, or decorative banners are emitted on stdout in `json` mode.
2. **Monotonicity**: `sequence` increases by 1 with each emitted event.
3. **Span Finalization**: All open spans are automatically closed with `status = "interrupted"` or `"ok"` during invocation unwind.
