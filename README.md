# Clingy

**Declarative CLI Engine for Lua**

[![Test Suite](https://img.shields.io/badge/tests-157%20passed-brightgreen.svg)]()
[![IR Schema](https://img.shields.io/badge/IR-clingy.command--graph.v0-blue.svg)]()
[![Machine Protocol](https://img.shields.io/badge/protocol-clingy.events.v1-purple.svg)]()

Clingy is a deterministic, declarative CLI engine for Lua. It separates command topology, lexical grammar, and execution lifecycles from semantic value validation (powered by [Valua](https://github.com/moonstone-lua/valua)).

---

## 1. Features

- **Pure Table DSL**: Clean, functional table combinators (`c.create`, `c.node`, `c.inherit`, `c.arg`, `c.option`, `c.flag`).
- **Normalized Command Graph IR**: Introspectable, immutable `clingy.command-graph.v0` intermediate representation.
- **Fast Two-Stage Router**: Precomputed $O(1)$ visible bindings and child maps ($\sim$110k ops/sec).
- **Multi-Segment Grammar Modes**: `interspersed`, `leading`, and `ordered` pipeline grammar per segment.
- **Transactional Short Clusters**: All-or-nothing opt-in flag clustering (`-xvf`).
- **Valua Standard Schema Integration**: Adapts raw string tokens to native types based on reflected schema input domains.
- **Structured Scopes & LIFO Deferrals**: Deterministic resource cleanup with multi-error aggregation.
- **Process Supervision**: Explicit lifecycle tracking (`declared` $\to$ `reaped`) and isolated control IPC.
- **Distinct Signal Semantics**: Preserves `SIGINT` vs `SIGTERM` with escalation state management.
- **Unified Terminal Composer**: Single owner of terminal output supporting `fancy`, `plain` (zero ANSI), `quiet`, and `json` (`clingy.events.v1` NDJSON) presentation.
- **Structured Help**: Automatically formats command documentation distinguishing local vs inherited options.

---

## 2. Quickstart

### Minimal CLI

```lua
local c = require("clingy")
local v = require("valua")

local app = c.create({
  name = "greet",
  version = "1.0.0",
  description = "A friendly greeting CLI",

  c.root(c.node({
    c.option("-g", "--greeting", v.string(), { default = "Hello" }),
    c.arg("name", v.string()),

    c.run(function(ctx)
      ctx.composer:log("info", string.format("%s, %s!", ctx.args.greeting, ctx.args.name))
      return 0
    end),
  })),
})

app:run(arg)
```

---

## 3. Nested Commands & Explicit Inheritance

```lua
local app = c.create({
  name = "meteorite",
  version = "1.0.0",

  c.root(c.node({
    -- Global flags cascade downward to all subcommands
    c.inherit(
      c.flag("-v", "--verbose"),
      c.flag("-q", "--quiet"),
      c.flag("--json")
    ),

    init = c.node({
      c.arg("profile", v.picklist({ "development", "production", "test" })),

      instant = c.node({
        c.flag("-n", "--now"),
        c.run(function(ctx)
          ctx:result({ status = "scaffolded", profile = ctx.args.profile, now = ctx.args.now })
        end),
      }, {
        description = "Instantly scaffold project",
      }),
    }, {
      description = "Initialize project environment",
    }),
  })),
})
```

---

## 4. Parser Grammar Policies

```lua
-- Leading Mode: options must precede positionals
c.node({
  c.leading(),
  c.flag("-f", "--force"),
  c.arg("src", v.string()),
  c.arg("dst", v.string()),
})

-- Ordered Pipeline Mode: strict declared sequence
c.node({
  c.ordered(),
  c.flag("--prepare"),
  c.arg("input", v.string()),
  c.flag("--commit"),
  c.arg("output", v.string()),
})

-- Short Flag Clustering: expands -xfv -> -x -f -v
c.node({
  c.short_clusters(),
  c.flag("-x", "--extract"),
  c.flag("-f", "--force"),
  c.flag("-v", "--verbose"),
})
```

---

## 5. Structured Scopes & Resource Deferral

```lua
c.run(function(ctx)
  ctx:scope(function(scope)
    local tmp = io.open("/tmp/build.log", "w")
    scope:defer(function()
      tmp:close()
      os.remove("/tmp/build.log")
    end)

    -- Spawns a supervised subprocess attached to this scope
    local proc = scope:spawn({ argv = { "zig", "build" } })
    local exit_code = proc:wait()
    return exit_code
  end)
end)
```

---

## 6. Signal Policies & Shutdown Escalation

```lua
c.signals({
  interrupt = function(ctx)
    if ctx:confirm("Abort build in progress?", { default = false }) then
      return c.signal.shutdown()
    end
  end,

  terminate = function(ctx)
    -- SIGTERM triggers immediate graceful shutdown
    return c.signal.shutdown()
  end,
})
```

---

## 7. Presentation Modes

- **`auto`**: Default. Selects `fancy` on interactive TTY, or `plain` in CI/pipes.
- **`plain`**: Emits **zero ANSI escape codes**; reduces progress spam to milestones.
- **`quiet`**: Suppresses progress, spans, and telemetry; preserves errors and results.
- **`json`**: Monotonic stream of NDJSON events adhering to `clingy.events.v1`.

```bash
meteorite init development instant --json > stream.ndjson
```

---

## 8. Documentation Index

- [`docs/DSL.md`](docs/DSL.md): Declarative table DSL reference.
- [`docs/COMMAND_GRAPH.md`](docs/COMMAND_GRAPH.md): Normalized Command Graph IR (`clingy.command-graph.v0`) specification.
- [`docs/PARSING_SEMANTICS.md`](docs/PARSING_SEMANTICS.md): Multi-segment token parsing and grammar modes.
- [`docs/RUNTIME_LIFECYCLE.md`](docs/RUNTIME_LIFECYCLE.md): Invocation lifecycle DAG and structured scopes.
- [`docs/PROCESSES_AND_SIGNALS.md`](docs/PROCESSES_AND_SIGNALS.md): Subprocess supervision, I/O modes, and signals.
- [`docs/OUTPUT_AND_EVENTS.md`](docs/OUTPUT_AND_EVENTS.md): Terminal Composer and standard stream contracts.
- [`docs/MACHINE_PROTOCOL.md`](docs/MACHINE_PROTOCOL.md): NDJSON protocol specification (`clingy.events.v1`).
- [`docs/PLATFORM_SUPPORT.md`](docs/PLATFORM_SUPPORT.md): OS and Lua runtime compatibility matrix.
- [`docs/CLINGY_RUNTIME_SUBSTRATE_AUDIT.md`](docs/CLINGY_RUNTIME_SUBSTRATE_AUDIT.md): Substrate audit report.
- [`CLINGY_V0_RELEASE_COMPLIANCE.md`](CLINGY_V0_RELEASE_COMPLIANCE.md): 22-section release compliance verdict.

---

## 9. License

MIT License. Built for the Moonstone Lua Ecosystem.
