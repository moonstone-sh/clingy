# Clingy Terminal Output, Composition, and Events (`docs/OUTPUT_AND_EVENTS.md`)

## 1. Single Composer Ownership

Clingy enforces the architectural invariant:
> **Exactly one component owns terminal composition at a time.**

The `Composer` instance owns:
- ANSI terminal state and color styling.
- Interactive spinners, live progress bars, and status redraws.
- Interactive prompt rendering (`ctx:confirm`).
- Semantic reduction into clean plain text for non-TTY / CI environments.

---

## 2. Presentation Modes

| Mode | Target Environment | Characteristics |
|---|---|---|
| **`fancy`** | Interactive TTY | Rich terminal UI, live spinner, multi-task progress bars, ANSI colors, UTF-8 status symbols (`✔`, `✖`). |
| **`plain`** | CI / Pipes / Non-TTY | **Zero ANSI escape sequences**; progress ticks reduced to semantic start/completion milestones; clean script-readable text. |
| **`quiet`** | Headless / Scripts | Suppresses spans, progress, and informational logs; preserves critical errors (`fatal`, `error`) and command `result` output. |
| **`json`** | Machine Pipelines | Strictly monotonic stream of NDJSON protocol envelopes (`clingy.events.v1`); zero ANSI or human prose outside envelopes. |
| **`auto`** | Default | Automatically selects `fancy` if standard output is an interactive TTY, or `plain` if running in CI / piped. |

---

## 3. Standard Streams Contract (stdout vs stderr)

Clingy maintains an explicit separation between stdout and stderr:

- **`stdout`**: Reserved for requested command payload data, final `ctx:result(...)` output, and NDJSON machine streams in `json` mode.
- **`stderr`**: Reserved for operational logs, diagnostics, progress feedback, spans, and fatal error reporting.

This guarantees that redirected output:
```bash
meteorite build --json > output.ndjson
```
receives pure, valid NDJSON envelopes without decorative human terminal text.
