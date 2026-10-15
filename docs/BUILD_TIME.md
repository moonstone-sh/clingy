# Build time and run time

Status: design note with a measured spike (`spikes/build-time/`), 2026-10-15.
Nothing in `src/` changed.

Clingy already works like a compiler: declarations (`clingy.dsl`) normalize
into the command graph (`clingy.command-graph.v0`), which compiles into a
router (`clingy.compiled-router.v0`). See
[CURRENT_TRUNK_ARCHITECTURE.md](CURRENT_TRUNK_ARCHITECTURE.md). Today every
stage runs in the user's process on every invocation. This note proposes
moving the line: declare and compile at build time, ship the compiled router
as data, and run only the parser, the handlers and validation.

Meteorite already works this way ("Lua declares. Ballad materializes."), and
keeps a hybrid mode for development. Clingy would do the same: `c.create`
stays exactly as it is, and a built CLI is an additional release path.

## What the spike measured

`spikes/build-time/` holds the README greet CLI, plus an integer `--times`
option (one flag, two options, one argument, one handler), in three forms:

| Path | What runs per invocation |
| --- | --- |
| dev (`run_dev.lua`) | `require("clingy")`, `c.create(declaration)`, `app:run(argv)` |
| built (`run_built.lua`) | `require("greet.graph")` (generated data), `clingy.app.create_app`, `app:run(argv)` |
| bundle (`run_bundle.lua`) | the built path, bundled by Quaver strict into one 187 KB file |

All three gave identical output and exit codes for 8 argument sets
(success, flags, integer coercion, validation failure, missing argument,
unknown flag, missing value) on Lua 5.4 and LuaJIT 2.1.

| | Modules loaded | Heap after run |
| --- | --- | --- |
| dev | 39 Clingy + 59 Valua | 642 KB |
| built | 18 Clingy + 7 Valua | 214 KB |

Process time over a bare interpreter, median of 150 interleaved runs
(`bench.py`), on an Apple Silicon Mac:

| | Lua 5.4 | LuaJIT 2.1 |
| --- | --- | --- |
| dev | +10.2 ms | +10.2 ms |
| built | +3.6 ms | +3.6 ms |

Later runs on a busier machine gave larger absolute numbers (dev +16 ms,
built +5 to 6 ms) but the same ratio. The built path removes about two thirds
of Clingy's startup cost. The bundle starts as fast as the built path, but
no faster: compiling one 187 KB chunk costs about what the module search
saves. Bundling is for distribution (one file, no `LUA_PATH`), not speed.

Compiling itself is cheap (`c.create` takes about 0.1 ms). The win is the
code the built path never loads: the DSL, the compiler, help, completion
(18 modules, including four shell backends), test presentation hosts, and
all of Valua except the schemas the CLI uses.

The 18 Clingy modules that remain are the runtime: `app`, `parser`,
`routing`, `form`, `named`, `adapter`, `context`, `scope`, `process`,
`lifecycle`, `signals`, `events`, `composer`, `presentation.{composer,host,prompt}`,
`compat`, and `util`.

## What a build produces

1. **The router as data.** A generated Lua module that returns the
   compiled router. Shared tables are hoisted, everything else is a table
   constructor, and keys are sorted so output is reproducible. The greet CLI's
   module is 3 KB.
2. **References instead of functions.** Handlers, dynamic completion
   providers and schemas are written as `require("module")["export"]`. The
   requires must be literal, so Quaver and other static tools can follow
   them. The spike's first version aliased `local R=require`, and Quaver
   rejected it with QV102.
3. **Precomputed coercion.** Today `adapter.coerce` calls `valua.reflect`
   on every value it converts, to learn whether the schema is an integer,
   number or boolean. That is build-time information. The build records the
   kind per schema, and the runtime converts tokens with a table lookup.
   This is also why the dev path loads all 59 Valua modules even when the CLI
   imports only `valua.schemas.string`.
4. **Later:** completion scripts per shell, pre-rendered help and man pages.
   These become files the package ships instead of code that runs.

Build-time validation comes for free: `validate_graph` errors (alias
conflicts, positional order, inheritance) fail the build instead of a user's
first run.

## The rule for functions

A built graph can't contain closures, so every function and schema in a
declaration must be an export of a runtime module:

```lua
-- greet/handlers.lua
local M = {}
function M.greet(ctx) ... end
return M

-- greet/cli.lua (the declaration)
local handlers = require("greet.handlers")
...
c.run(handlers.greet)
```

The spike finds references by identity: it indexes the exports of the
declared runtime modules, and any other function fails the build with its
path (`function at built.router.graph.bindings.root:greeting.schema._run is
not an export of a runtime module`). That keeps today's API: no new
`c.run("module#name")` form is needed, and an inline `c.run(function ... end)`
still works with `c.create`. It only fails the release build, with a message
that names the declaration. This matches Meteorite's rule that hybrid handlers
can't capture outer locals.

## Changes Clingy needs (found by the spike)

1. **Stop cloning schemas.** `flatten_declarations` in `compiler.lua` uses
   `util.deep_copy(item)`, which copies each declaration's schema and its
   metatable. The compiled graph therefore never holds the user's schema
   objects, and nothing can refer to them. The spike patched `deep_copy` to
   keep module exports by identity. The real fix is to copy only the
   declaration's own fields. That also helps today: less copying, and schema
   identity is preserved for anything that compares schemas.
2. **Typed access without declaration identity.** `ctx:get(decl)` looks up
   `decl_map`, which is keyed by declaration tables (8 entries in the greet
   CLI). A built CLI has no declaration tables. `examples/modular-leaf` shows
   why this matters: `run.lua` requires `cli.build.args` to call
   `ctx:get(args.target)`. That module requires `clingy` and `valua`, so it
   would load everything the build removed. Options:
   - resolve `ctx:get(decl)` through `decl.result_key`, a plain string the
     declaration already has, and keep `decl_map` only as a dev fallback;
   - or have the build generate an `args` module of plain keys plus LuaLS
     types (TYPING.md), so handlers stop importing declarations.
   The first is a small change; the second is the better end state.
3. **Store the coercion kind on the binding.** Compute it in
   `compile_router` (dev) or the build (release), and let `adapter.coerce`
   reflect only when it is missing. The dev path gets faster too.
4. **A runtime entry.** `require("clingy.runtime").run(built, argv)`, which
   loads only the 18 runtime modules. The facade (`require("clingy")`) stays
   for declarations and dev.
5. **A Ballad node.** `clingy.build` in a partiture: the declaration module
   and runtime modules in, the generated router module out (and later
   completion scripts and help). Quaver can follow it for a one-file
   artifact.

## Quaver and one-file CLIs

The built greet CLI bundles in strict mode with Quaver main
(`format = "bundle"`, `minify = { level = "compact" }`, `externals = { lfs = true }`):
95 modules, 187 KB, and it runs with no `LUA_PATH` on Lua 5.4 and LuaJIT.
`mangle` is refused (QV111) because `clingy.compat` uses reflective
functions. That is expected, and compact is the right level for a CLI.

The bundle includes every module reachable by a literal require, but only
executes the ones the run needs. A Quaver facade profile for Valua would also
shrink the file. It won't change startup, which already loads only seven
Valua modules.

## Open decisions

- **Typed access** (change 2): string fallback first, or go straight to
  generated `args` modules?
- **Where the build lives**: a `clingy.build` module in this package (the
  generator has to understand the graph) plus a thin Ballad node, or a
  separate package?
- **Format stability**: is `clingy.built-router.v0` a public format (other
  tools read it: LuaLS, docs, completion) or private to one Clingy version?
  The spike's file mirrors the compiled router, including `raw_node` and
  `graph`, which duplicates data. A real format should store the graph once
  and rebuild the lookup tables at load, if that stays cheap.

## Reproducing

```sh
cd spikes/build-time
export VALUA_SRC=<valua checkout>/src
export LUA_PATH="./?.lua;../../src/?.lua;../../src/?/init.lua;$VALUA_SRC/?.lua;$VALUA_SRC/?/init.lua;;"
lua build.lua                                     # writes greet/graph.lua
lua <quaver>/src/main.lua build quaver.config.lua greet.bundle.lua
lua run_dev.lua -n 3 Ada                          # today's path
lua run_built.lua -n 3 Ada                        # built path
lua run_bundle.lua -n 3 Ada                       # one file
python3 -I bench.py                               # medians over 150 runs
```

The spike patches Clingy at build time (`util.deep_copy`) and at run time
(`adapter.coerce`) where the changes above are missing. It is not a library.
