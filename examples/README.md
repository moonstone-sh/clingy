# Clingy v0 — Example Moonstone Projects

This directory contains standalone, executable Moonstone projects demonstrating Clingy v0's architecture, modular routing, typing, and LuaLS editor integration.

Each fixture is a self-contained Moonstone project initialized with `moon init` and configured with a dedicated `.luarc.json` for Neovim and LuaLS.

---

## Example Projects

### 1. [`hello/`](hello/) — Minimal Positional CLI
The smallest useful Clingy project: a required name, an optional `--shout`, and
a structured greeting result.

```bash
cd examples/hello
moon exec lua src/main.lua Ada --shout
# HELLO, ADA!
```

### 2. [`calculator/`](calculator/) — Typed Definitions and JSON
Runs arithmetic in a selected integer base. Repeated `-D` records accept `=`,
space, and hyphen separators; `--json` selects NDJSON output.

```bash
cd examples/calculator
moon exec lua src/main.lua --json -Dbase=8 add 7 1
# {"operation":"add","left":7,"right":1,"base":8,"result":"10","result_decimal":8}
```

The `result` field uses the selected base, while `result_decimal` remains a
decimal number for consumers that need a numeric value. Division is integer
only and rejects non-integral results.

### 3. [`advanced-grammar/`](advanced-grammar/) — Composed and Forwarded Grammar
Combines typed `dev:database=true`, repeated definition records, colon option
separators, and `--` forwarding via the canonical `c.tail` declaration. Running
without arguments uses a useful demo.

```bash
cd examples/advanced-grammar
moon exec lua src/main.lua
# [INFO] Parsed environment=dev database=true profile=demo
# [INFO] Forwarded tokens: -- tool --verbose
# Advanced grammar: dev (database=true, profile=demo)
```

The explicit form is the same grammar with caller-supplied values. Moonstone's
`moon exec` wrapper consumes a literal `--` before it reaches the example, so
run the script directly inside the project environment when checking the
forwarding delimiter:

```bash
moon exec sh -c 'lua src/main.lua dev:database=false -Dmode=debug --profile:ci "$(printf "%s%s" "-" "-")" tool --verbose'
# [INFO] Parsed environment=dev database=false profile=ci
# [INFO] Forwarded tokens: -- tool --verbose
# Advanced grammar: dev (database=false, profile=ci)
```

### 4. [`meteorite/`](meteorite/) — Canonical Multi-Command Architecture
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

### 5. [`modular-leaf/`](modular-leaf/) — Modular Router Assembly
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

### 6. [`grammar-modes/`](grammar-modes/) — Parser Ordering & Passthrough
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

### 7. [`subprocess-lifecycle/`](subprocess-lifecycle/) — Managed Subprocesses & Scopes
Demonstrates managed child processes, resource scopes, and deterministic LIFO cleanup:
* `ctx:scope(fn)`: Structured resource management.
* `scope:defer(fn)`: Cleanup callbacks guaranteed to unwind in reverse order on success, failure, or signal.
* `ctx:spawn(opts)`: Explicit subprocess lifecycle states (`declared` &rarr; `spawning` &rarr; `running` &rarr; `reaped`).

```bash
cd examples/subprocess-lifecycle
moon exec lua src/main.lua worker -t 4 -v
```

---

### 8. [`json-stream-events/`](json-stream-events/) — Machine NDJSON Protocol
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

## Shell Completions

All example projects implement first-class shell completions powered by Clingy's `CompletionEngine`:
- **Schema-Derived Autocomplete**: Picklists and enums (e.g. `v.picklist({ "development", "production", "test" })`) are discovered automatically.
- **Filesystem Completions**: Options and positionals use `c.complete(c.directory(), ...)` or `c.complete(c.file(), ...)` delegating natively to host shells.
- **Dynamic Context Inspection**: In `subprocess-lifecycle`, worker task names adapt dynamically to preceding `--tasks` arguments (`runner worker --tasks 4 <TAB>` &rarr; `job-01..job-04`).
- **Structured Descriptions**: In `json-stream-events`, `--profile` options provide rich candidate descriptions formatted natively for Zsh, Fish, and PowerShell.

### Generating & Installing Completions

Each example includes a built-in `completion` command generating thin, lightning-fast integration shims for **Bash**, **Zsh**, **Fish**, and **PowerShell**:

```bash
# 1. Meteorite
moon exec lua src/main.lua completion zsh > ~/.zsh/completion/_meteorite
moon exec lua src/main.lua completion bash > ~/.local/share/bash-completion/completions/meteorite
moon exec lua src/main.lua completion fish > ~/.config/fish/completions/meteorite.fish
moon exec lua src/main.lua completion powershell > "$HOME/.meteorite.ps1"

# 2. Dynamic evaluation directly in your active shell:
eval "$(moon exec lua examples/meteorite/src/main.lua completion zsh)"
eval "$(moon exec lua examples/modular-leaf/src/main.lua completion bash)"
```

### Testing Completions from the CLI

You can query the hidden machine completion endpoint directly from your terminal:

```bash
# Propose subcommands at root:
moon exec lua src/main.lua --__clingy-complete zsh meteorite "" --cword 2

# Propose schema-derived picklist choices for 'init':
moon exec lua src/main.lua --__clingy-complete zsh meteorite init "" --cword 3

# Propose dynamic context-aware job names based on '--tasks 3':
moon exec lua examples/subprocess-lifecycle/src/main.lua --__clingy-complete zsh runner worker --tasks 3 "" --cword 5
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
