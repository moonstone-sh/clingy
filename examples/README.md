# Clingy v0 — Examples

This directory contains executable reference implementations showcasing Clingy v0's declarative CLI engine.

---

## Example Overview

### 1. Canonical Meteorite CLI ([`meteorite.lua`](meteorite.lua))
Demonstrates the full declarative table DSL from Section 47 of the Clingy specification:
* Root global inheritance (`c.inherit(c.flag("-v", "--verbose"))`).
* Subtree inheritance (`init` inherits `--json` into `instant`).
* Cardinality algebra with repeated build flags (`c.repeated(c.option("-D", "--define", Define))`).
* Strict ordered grammar pipeline (`c.ordered()`).
* Opt-in short flag clustering (`-vn` &rarr; `-v -n`).
* Signal handlers with custom interrupt behavior (`c.signals`).

```bash
# Run demo
moon exec lua examples/meteorite.lua

# Or with custom arguments
moon exec lua examples/meteorite.lua init development instant -vn
moon exec lua examples/meteorite.lua build -D "ENV=prod" -D "PORT=8080"
moon exec lua examples/meteorite.lua legacy --prepare src.dat --commit dst.dat
```

---

### 2. Managed Subprocesses & Scopes ([`subprocess_lifecycle.lua`](subprocess_lifecycle.lua))
Demonstrates managed child processes, resource scopes, and deterministic LIFO cleanup:
* `ctx:scope(fn)`: Scoped execution context.
* `scope:defer(fn)`: Cleanup callbacks guaranteed to unwind in reverse order on success, failure, or signal.
* `scope:spawn(spec)`: Explicit subprocess lifecycle states (`declared` &rarr; `spawning` &rarr; `running` &rarr; `reaped`).

```bash
moon exec lua examples/subprocess_lifecycle.lua
```

---

### 3. Machine NDJSON Event Stream ([`json_stream_events.lua`](json_stream_events.lua))
Demonstrates structured semantic event emission and NDJSON formatting:
* Attributed spans (`ctx:span`).
* Progress updates (`ctx:progress`).
* Standard log events (`ctx:log`).
* Return values wrapped in result envelopes.
* Guaranteed protocol adherence for external tool integration.

```bash
moon exec lua examples/json_stream_events.lua
```

---

### 4. Grammar Modes & `--` Passthrough ([`grammar_modes.lua`](grammar_modes.lua))
Demonstrates parser behavior across different grammar policies:
* **Interspersed (`c.interspersed`)**: Modern CLI mode where options may appear anywhere relative to positionals.
* **Leading (`c.leading`)**: Options must appear before positional arguments.
* **Ordered (`c.ordered`)**: Enforces strict declared sequence of options and arguments.
* **Passthrough (`c.passthrough`)**: Raw preservation of tokens after `--` without shell parsing or alteration.

```bash
moon exec lua examples/grammar_modes.lua
```
