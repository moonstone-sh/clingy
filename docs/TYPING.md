# Typing in Clingy — Developer Guide

> **Core Philosophy:** Inline by default. Name a binding when its identity matters.

Clingy provides a clean, escalating type experience that grows alongside your project's complexity without imposing premature boilerplate.

---

## 1. Architectural Progression

Clingy supports four escalating declaration and typing styles:

```text
INLINE (Standard Everyday Style)
  anonymous declarations
  inline handler
  ctx.args.foo
      ↓ (complexity earns identity)
NAMED BINDINGS (Explicit Identity)
  local foo = c.arg(...)
  ctx:get(foo)
      ↓ (complexity earns modules)
MODULAR LEAF (Multi-Command Topology)
  require("cli.init")
  require("cli.build")
      ↓ (command becomes substantial)
SEPARATED ASSEMBLY (Architecture at Scale)
  args.lua
  run.lua
  node.lua
```

All styles compile into the exact same **Command Graph IR** and provide identical runtime behavior.

---

## 2. Style 1: Inline Declarations (Canonical Style)

Inline declarations are the standard, recommended everyday syntax for Clingy applications. You do not need to assign declarations to local variables merely to get autocomplete or type checking.

```lua
local c = require("clingy")
local v = require("valua")

local Directory = v.string()
local Header = v.string()

return c.node({
  c.arg("dirname", Directory),
  c.flag("-f", "--force"),
  c.repeated(
    c.option("-H", "--header", Header)
  ),

  c.run(function(ctx)
    -- ctx.args is automatically typed by Clingy's LuaLS plugin:
    local dir = ctx.args.dirname -- type: Directory (string)
    local force = ctx.args.force -- type: boolean
    local headers = ctx.args.header -- type: Header[]|nil
  end),
})
```

---

## 3. Style 2: Named Bindings (Identity Access)

Named bindings are first-class and useful when a declaration's **identity itself matters**—for instance, when sharing references across helper functions, testing handlers in isolation, or working in editor environments without plugin support.

```lua
local c = require("clingy")
local v = require("valua")

local dir_arg = c.arg("dirname", v.string())
local force_flag = c.flag("-f", "--force")

local function perform_action(ctx)
  -- Type-safe resolution by declaration handle:
  local dir = ctx:get(dir_arg)
  local force = ctx:get(force_flag)
end

return c.node({
  dir_arg,
  force_flag,
  c.run(perform_action),
})
```

`ctx:get(binding)` resolves by table pointer equality (`rawequal`), guaranteeing unambiguous lookups regardless of key spelling.

---

## 4. Style 3: Modular Leaf Nodes

When a CLI has multiple subcommands, the root file defines command topology while individual subcommands live in dedicated leaf modules.

### `src/cli/init.lua` (Leaf Module)
```lua
local c = require("clingy")
local v = require("valua")

return c.node({
  c.arg("project_name", v.string()),
  c.flag("-f", "--force"),

  c.run(function(ctx)
    ctx:result({ project = ctx.args.project_name, force = ctx.args.force })
  end),
})
```

### `src/cli/root.lua` (Topology Assembly)
```lua
local c = require("clingy")

return c.create({
  name = "meteorite",
  version = "1.0.0",

  c.root(c.node({
    init = require("cli.init"),
    build = require("cli.build"),
    dev = require("cli.dev"),
  })),
})
```

---

## 5. Style 4: Separated Command Decomposition

For complex enterprise commands with dozens of flags and multi-stage execution pipelines, you can cleanly separate declarations, handler logic, and node assembly into dedicated files.

```text
src/cli/init/
├── args.lua   # Declaration handles
├── run.lua    # Execution logic & business rules
└── node.lua   # Node wiring & metadata
```

### `src/cli/init/args.lua`
```lua
local c = require("clingy")
local v = require("valua")

return {
  dirname = c.arg("dirname", v.string()),
  force = c.flag("-f", "--force"),
  profile = c.option("-p", "--profile", v.picklist({ "dev", "prod" })),
}
```

### `src/cli/init/run.lua`
```lua
local args = require("cli.init.args")

return function(ctx)
  local dir = ctx:get(args.dirname)
  local force = ctx:get(args.force)
  local profile = ctx:get(args.profile) or "dev"

  ctx:log("info", string.format("Initializing %s (%s)", dir, profile))
end
```

### `src/cli/init/node.lua`
```lua
local c = require("clingy")
local args = require("cli.init.args")
local run = require("cli.init.run")

return c.node({
  args.dirname,
  args.force,
  args.profile,

  c.run(run),
}, {
  description = "Initialize a new project environment",
})
```

---

## 6. Cardinality Type Algebra

Clingy's cardinality algebra maps declaration kinds and modifiers into strict static types:

| Constructor / Modifier | Min Occurrence | Max Occurrence | Default Value | Resulting Type in `ctx:get()` & `ctx.args` |
| :--- | :--- | :--- | :--- | :--- |
| `c.flag(...)` | 0 | 1 | `false` | `boolean` |
| `c.option(..., Schema<I, O>)` | 0 | 1 | `nil` | `O \| nil` |
| `c.required(c.option(..., Schema<I, O>))` | 1 | 1 | `nil` | `O` |
| `c.arg(..., Schema<I, O>)` | 1 | 1 | `nil` | `O` |
| `c.optional(c.arg(..., Schema<I, O>))` | 0 | 1 | `nil` | `O \| nil` |
| `c.repeated(c.option(..., Schema<I, O>))` | 0 | Unbounded | `nil` | `O[] \| nil` |
| `c.required(c.repeated(c.option(...)))` | 1 | Unbounded | `nil` | `O[]` |
| `c.repeated(c.arg(..., Schema<I, O>))` | 1 | Unbounded | `nil` | `O[]` |
| `c.passthrough("key")` | 0 | 1 | `nil` | `string[]` |

---

## 7. Dual-Access Key Conventions

Clingy automatically establishes dual-access mappings for kebab-case and snake_case keys in `ctx.args`:

```lua
c.option("--dry-run")

c.run(function(ctx)
  -- Both access patterns are fully valid and resolve to the identical value:
  local a = ctx.args.dry_run
  local b = ctx.args["dry-run"]
end)
```
