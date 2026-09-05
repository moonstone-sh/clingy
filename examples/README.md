# Clingy v0 — Example Moonstone Projects

This directory contains standalone, executable Moonstone projects demonstrating Clingy v0's architecture, modular routing, typing, and LuaLS editor integration.

Each fixture is a self-contained Moonstone project initialized with `moon init` and configured with a dedicated `.luarc.json` for Neovim and LuaLS.

---

## Example Projects

### 1. [`meteorite/`](meteorite/) — Canonical Multi-Command Architecture
Demonstrates the full declarative table DSL from Section 47 of the Clingy specification:
* Root global inheritance (`c.inherit(c.flag("-v", "--verbose"))`).
* Subtree inheritance (`init` inherits `--json` into `instant`).
* Cardinality algebra with repeated build flags (`c.repeated(c.option("-D", "--define", Define))`).
* Strict ordered grammar pipeline (`c.ordered()`).
* Opt-in short flag clustering (`-vn` &rarr; `-v -n`).
* Signal handlers with custom interrupt behavior (`c.signals`).

```bash
cd examples/meteorite
moon exec lua src/main.lua init development instant -vn
moon exec lua src/main.lua build -D "ENV=prod" -D "PORT=8080"
moon exec lua src/main.lua legacy --prepare src.dat --commit dst.dat
```

---

### 2. [`modular-leaf/`](modular-leaf/) — Modular Router Assembly
Demonstrates modular leaf composition and per-command directory decomposition:
* Root router topology assembling submodules (`init = require("cli.init")`, `build = require("cli.build.node")`).
* Clean separation of `args.lua`, `run.lua`, and `node.lua`.
* Shared grammar fragments (`c.group`) across independent commands.
* Type-safe binding resolution via `ctx:get(binding)`.

```bash
cd examples/modular-leaf
moon exec lua src/main.lua init my-project -f
moon exec lua src/main.lua build native -r -D OPT=3 -D ARCH=arm64
```

---

### 3. [`grammar-modes/`](grammar-modes/) — Parser Ordering & Passthrough
Demonstrates parser behavior across different grammar policies:
* **Interspersed (`c.interspersed`)**: Modern CLI mode where options may appear anywhere relative to positionals.
* **Leading (`c.leading`)**: Options must appear before positional arguments.
* **Ordered (`c.ordered`)**: Enforces strict declared sequence of options and arguments.
* **Passthrough (`c.passthrough`)**: Raw preservation of tokens after `--` without alteration.

```bash
cd examples/grammar-modes
moon exec lua src/main.lua inter src.txt dst.txt -f
moon exec lua src/main.lua leading -f src.txt dst.txt
moon exec lua src/main.lua ordered --prepare in.bin --commit out.bin
moon exec lua src/main.lua exec -- -Doptimize=ReleaseFast --flag "arg with space"
```

---

### 4. [`subprocess-lifecycle/`](subprocess-lifecycle/) — Managed Subprocesses & Scopes
Demonstrates managed child processes, resource scopes, and deterministic LIFO cleanup:
* `ctx:scope(fn)`: Structured resource management.
* `scope:defer(fn)`: Cleanup callbacks guaranteed to unwind in reverse order on success, failure, or signal.
* `ctx:spawn(opts)`: Explicit subprocess lifecycle states (`declared` &rarr; `spawning` &rarr; `running` &rarr; `reaped`).

```bash
cd examples/subprocess-lifecycle
moon exec lua src/main.lua worker -t 4 -v
```

---

### 5. [`json-stream-events/`](json-stream-events/) — Machine NDJSON Protocol
Demonstrates structured semantic event emission and NDJSON formatting:
* Attributed spans (`ctx:span`).
* Progress updates (`ctx:progress`).
* Standard log events (`ctx:log`).
* Return values wrapped in result envelopes.

```bash
cd examples/json-stream-events
moon exec lua src/main.lua --json compile desktop -o dist
```

---

## Neovim & LuaLS Integration

Each example project contains a `.luarc.json` configured with:

```json
{
  "workspace": {
    "library": [
      ".moonstone/env/share/lua/5.4",
      "../../luals/library"
    ],
    "checkThirdParty": false,
    "runtime.plugin": "../../luals/plugin.lua"
  }
}
```

When opened in Neovim:
1. **Live `ctx.args` Autocomplete**: Typing `ctx.args.` inside `c.run(function(ctx) ... end)` presents autocomplete for all declared args, flags, and options with exact Valua output types.
2. **First-Class `Binding<O>` Handles**: Local declaration variables (`local dir = c.arg(...)`) provide full hover type info and typed returns on `ctx:get(dir)`.
3. **Zero Configuration**: No code generation or pre-compilation is required.
