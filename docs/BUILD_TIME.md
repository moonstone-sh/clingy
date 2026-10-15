# Build time and run time

Clingy works like a compiler: declarations (`clingy.dsl`) normalize into the
command graph (`clingy.command-graph.v0`), which compiles into a router. See
[CURRENT_TRUNK_ARCHITECTURE.md](CURRENT_TRUNK_ARCHITECTURE.md). With
`c.create`, every stage runs in the user's process on every invocation.

`clingy.build` moves the line: it compiles the declaration once and writes
the graph as a Lua module ([BUILT_FORMAT.md](BUILT_FORMAT.md)).
`clingy.runtime` runs that module with only the parser, routing, handlers and
validation. `c.create` is unchanged and stays the development path, the way
Meteorite keeps a hybrid mode beside its static build.

## Using it

```lua
-- greet/handlers.lua: handlers live in a module.
local M = {}

---@param ctx greet.built.args.root.context
function M.greet(ctx)
  ctx:log("info", "Hello, " .. ctx.args.name .. "!")
end

return M
```

```lua
-- greet/cli.lua: the declaration, as for c.create.
local c = require("clingy")
local v = require("valua")
local handlers = require("greet.handlers")

return {
  name = "greet",
  root = c.node({
    c.arg({ key = "name", schema = v.string() }),
    c.run(handlers.greet),
  }),
}
```

```lua
-- build.lua: run whenever the declaration changes.
require("clingy.build").write({ declaration = "greet.cli", module = "greet.built" })
-- writes greet/built.lua and greet/built/args.lua (the directories must exist)
```

```lua
-- main.lua: the CLI's entry.
os.exit(require("clingy.runtime").run(require("greet.built"), arg))
```

`clingy.build.build(opts)` returns the generated sources without writing them
(`{ files = { [path] = source }, modules = { [name] = source } }`), for build
tools such as a Ballad node. `examples/build-time/` is a complete example,
including a Quaver bundle and a benchmark.

## Rules

- **Functions must be module exports.** Handlers, signal handlers, stage
  callbacks and `c.dynamic` callbacks are written as
  `require("module").export`. The build finds them by identity among the
  exports of modules the declaration required, so `c.run(handlers.greet)`
  needs no new API. An inline `c.run(function ... end)` still works with
  `c.create`; the build fails and names its place
  (`function at root.nodes.root.handler ...`).
- **Schemas are exports or recreated.** An exported schema is referenced.
  An inline Valua schema is recreated from Valua's individual modules when
  it uses only string, integer, number, boolean, literal, picklist,
  optional, `v.describe`, and `v.pipe` with length, value, pattern, prefix,
  suffix, `non_empty` and `multiple_of` actions, with or without custom
  messages. The build proves each copy by comparing `valua.reflect` of the
  copy and the original. Anything else (`v.check`, `v.transform`, objects,
  arrays, unions, other schema libraries) must be exported from a module.
- **Completion providers are recreated** from their kind and data
  (`c.values`, `c.file`, `c.path`, `c.directory`, `c.none`; `c.dynamic` with
  an exported callback).
- **Typed access goes through the generated args module.**
  `ctx:get(decl)` looks declarations up by identity, and a built CLI has no
  declaration objects. The args module declares, per command, a context type
  (`---@param ctx greet.built.args.root.context` types `ctx.args`) and a
  table of result keys for `ctx:get(args.root.name)`. The annotation is
  type-only, so handlers need not require the module. On a first build,
  before the module exists, `clingy.build` provides a stand-in whose fields
  are their own names.
- **Keep runtime modules light.** A handler module that requires `clingy` or
  `valua` loads all of it again at run time. Require individual modules
  instead (`require("valua.schemas.integer")`).

## What changed in Clingy

- `clingy.compiler` no longer deep-copies schemas and functions into the
  graph (it copied each schema and its metatable). Graph bindings hold the
  declared schema objects.
- `clingy.adapter` caches schema inspection per schema. Coercion used to run
  `valua.reflect` on every value it converted, which also loaded all of
  Valua. Built CLIs preload the inspections, and never reflect.
- `clingy.router` holds the router compiler, so the runtime doesn't load the
  DSL normalizer. `clingy.compiler.compile_router` is the same function.
- `clingy.build`, `clingy.runtime`, and the
  [built format](BUILT_FORMAT.md) are new.

## Measurements

`examples/build-time/` (the README greet CLI plus an integer `--times`
option). Identical output and exit codes for 8 argument sets, on Lua 5.4 and
LuaJIT 2.1, for `c.create`, the built CLI, and the Quaver bundle.

| | Modules loaded | Heap after run |
| --- | --- | --- |
| `c.create` | 39 Clingy + 59 Valua | about 640 KB |
| built | 20 Clingy + 9 Valua | about 215 KB |

Process time over a bare interpreter, median of 150 interleaved runs
(`bench.py`) on an Apple Silicon Mac. The first row is the design spike on
a quiet machine; the second is this implementation on a busier one. The ratio
held: the built path removes about two thirds of Clingy's startup cost.

| | `c.create` | built | Quaver bundle |
| --- | --- | --- | --- |
| spike, Lua 5.4 and LuaJIT | +10.2 ms | +3.6 ms | — |
| implementation, Lua 5.4 | +19.3 ms | +7.2 ms | +8.1 ms |
| implementation, LuaJIT | +19.4 ms | +7.0 ms | +6.1 ms |

The bundle (Quaver strict, `compact`, about 190 KB) starts about as fast as
the built module: compiling one large chunk costs about what the module
search saves. Bundling is for distribution: one file, no `LUA_PATH`.
`mangle` is refused (QV111) because `clingy.compat` uses reflective
functions.

## Decisions (2026-10-15)

- **Typed access:** generated args module, not a `result_key` fallback in
  `ctx:get`.
- **Where the build lives:** in this package (`clingy.build`); build tools
  wrap it.
- **Format:** public and versioned (`clingy.built.v1`).

LuaLS 3.18 does not infer the generic in `clingy.Binding<O>`, so
`ctx:get(binding)` returns an unnarrowed type for declaration objects too.
The generated context classes type `ctx.args` with plain fields, which LuaLS
checks (verified headless: a `string` assigned to `integer` and an unknown
field are both reported).

## Not done yet

- A Ballad node (`clingy.build` in a partiture) and a `clingy build` command.
- Completion scripts, help and man pages as build outputs.
- Inline handlers without upvalues (Meteorite extracts their source); today
  they must be exported.
