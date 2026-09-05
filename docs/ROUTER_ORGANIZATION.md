# Router Organization & Modular CLI Architecture

> **Guiding Principle:** Complexity should earn a name or module; Clingy does not require ceremony before it is useful.

Clingy does **not** expect you to put your entire CLI into a single giant router file. As your application grows, ordinary Lua module composition lets you split commands, arguments, and handlers naturally.

---

## 1. Escalating Project Layouts

### Pattern A: Single-File CLI (Tiny Tools & Utilities)
Best for standalone scripts, small developer tools, and micro-CLIs with 1–3 commands.

```text
my-cli/
├── src/
│   └── main.lua   # Full topology, declarations, and handlers in one file
└── moonstone.toml
```

```lua
local c = require("clingy")

local app = c.create({
  name = "tiny-tool",
  c.root(c.node({
    c.arg("path"),
    c.flag("-v", "--verbose"),
    c.run(function(ctx)
      print("Processing:", ctx.args.path)
    end),
  })),
})

return app:run()
```

---

### Pattern B: Root Topology + Leaf Modules (Medium CLI)
Best for multi-command applications (e.g. `init`, `build`, `test`, `deploy`). The root file defines the high-level tree while each subcommand is an isolated leaf node.

```text
my-cli/
├── src/
│   ├── cli/
│   │   ├── init.lua    # Leaf command node
│   │   ├── build.lua   # Leaf command node
│   │   └── test.lua    # Leaf command node
│   └── main.lua        # Root application wiring
└── moonstone.toml
```

#### `src/cli/init.lua`
```lua
local c = require("clingy")

return c.node({
  c.arg("name"),
  c.flag("-f", "--force"),
  c.run(function(ctx)
    -- handler logic
  end),
}, {
  description = "Initialize a new project",
})
```

#### `src/main.lua`
```lua
local c = require("clingy")

local app = c.create({
  name = "my-cli",
  version = "1.0.0",

  c.root(c.node({
    c.inherit(
      c.flag("-v", "--verbose"),
      c.flag("--json")
    ),

    init = require("cli.init"),
    build = require("cli.build"),
    test = require("cli.test"),
  })),
})

return app:run()
```

---

### Pattern C: Per-Command Directory Decomposition (Large Complex CLI)
Best for substantial commands featuring complex flag combinations, multi-stage pipelines, or extensive business logic.

```text
src/cli/build/
├── args.lua    # Declaration handles and Valua schemas
├── run.lua     # Execution logic, spans, and child processes
└── node.lua    # Node wiring and metadata
```

#### `src/cli/build/args.lua`
```lua
local c = require("clingy")
local v = require("valua")

return {
  target = c.arg("target", v.picklist({ "native", "wasm", "arm64" })),
  release = c.flag("-r", "--release"),
  jobs = c.option("-j", "--jobs", v.integer()),
  defines = c.repeated(c.option("-D", "--define")),
}
```

#### `src/cli/build/run.lua`
```lua
local args = require("cli.build.args")

return function(ctx)
  local target = ctx:get(args.target)
  local is_release = ctx:get(args.release)
  local jobs = ctx:get(args.jobs) or 4
  local defines = ctx:get(args.defines) or {}

  ctx:span("compilation", function()
    ctx:log("info", string.format("Building target %s (jobs=%d)", target, jobs))
    -- Process compilation logic
  end)
end
```

#### `src/cli/build/node.lua`
```lua
local c = require("clingy")
local args = require("cli.build.args")
local run = require("cli.build.run")

return c.node({
  args.target,
  args.release,
  args.jobs,
  args.defines,

  c.run(run),
}, {
  description = "Compile project artifacts",
})
```

---

## 2. Shared Grammar Modules (`c.group`)

Cross-cutting flags (such as output formatting, telemetry, or network proxies) can be packaged into reusable groups:

### `src/cli/shared/output.lua`
```lua
local c = require("clingy")

return c.group({
  c.flag("-q", "--quiet"),
  c.flag("--plain"),
  c.flag("--json"),
  c.option("-o", "--output"),
})
```

Mounting the group in multiple commands automatically flattens the declarations into each command's parser scope:

```lua
local shared_output = require("cli.shared.output")

return c.node({
  shared_output,
  c.arg("filename"),
  c.run(function(ctx) ... end),
})
```

---

## 3. The `require()` vs `dofile()` Invariant

When splitting declaration handles across files, always use Lua's standard `require()`.

### Why `require()` is Mandatory for Shared Bindings
- **`require("my.args")`** caches the returned table in Lua's global `package.loaded` registry.
- Every file importing `my.args` (`node.lua`, `run.lua`, etc.) receives the **exact same table memory address**.
- Table pointer equality (`rawequal`) is preserved, allowing `ctx:get(binding)` to resolve accurately.

```text
package.loaded["my.args"]
      │ (Cached Instance: table: 0x600003)
      ├──> require("my.args") in node.lua ===> table: 0x600003  ──┐ (Exact Match)
      └──> require("my.args") in run.lua  ===> table: 0x600003  ──┘
```

### Why `dofile()` Breaks Binding Identity
- **`dofile("my/args.lua")`** re-evaluates the file on every call, returning a **newly allocated table** each time.
- `node.lua` registers table `0xAAA`, but `run.lua` queries with table `0xBBB`.
- Because `rawequal(0xAAA, 0xBBB) == false`, `ctx:get(binding)` cannot match the registered declaration handle.

```text
dofile("args.lua") in node.lua ===> Allocated table: 0x001000  ──┐ (Mismatch!)
dofile("args.lua") in run.lua  ===> Allocated table: 0x002000  ──┘
```

> **Summary:** Always structure modular CLI files as standard Lua modules loaded with `require()`.
