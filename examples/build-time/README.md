# Built CLI

The greet CLI three ways: declared and compiled per run (`c.create`), built
ahead of time (`clingy.build` + `clingy.runtime`), and bundled into one file
by Quaver. See [Build time and run time](../../docs/BUILD_TIME.md).

| File | Role |
| --- | --- |
| `greet/cli.lua` | The declaration. Inline Valua schemas; the handler comes from a module. |
| `greet/handlers.lua` | Runtime module. Typed by the generated args module. |
| `build.lua` | Writes `greet/built.lua` and `greet/built/args.lua` (ignored by git). |
| `greet/main.lua` | Entry of the built CLI, a function of `argv`. |
| `run_dev.lua`, `run_built.lua`, `run_bundle.lua` | The three ways to run it. |
| `quaver.config.lua` | Quaver strict bundle of `greet.main`. |
| `bench.py` | Median startup of each, over a bare interpreter. |

```sh
export VALUA_SRC=<valua checkout>/src
export LUA_PATH="./?.lua;../../src/?.lua;../../src/?/init.lua;$VALUA_SRC/?.lua;$VALUA_SRC/?/init.lua;;"
lua build.lua
lua run_dev.lua -n 2 Ada
lua run_built.lua -n 2 Ada
lua <quaver checkout>/src/main.lua build quaver.config.lua greet.bundle.lua
LUA_PATH="" lua run_bundle.lua -n 2 Ada
python3 -I bench.py
```
