# Clingy Declarative Table DSL (`clingy/dsl.lua`)

## 1. Overview & Principles

Clingy's Domain Specific Language (DSL) is a **pure declarative table DSL**. It explicitly rejects imperative method-chaining builders (e.g. `c.command():option():inherit()`) in favor of nested Lua table syntax that mirrors the static topology of CLI applications.

Key characteristics:
1. **Homogeneous Nesting**: Numeric keys contain argument declarations, modifiers, handlers, and parser policies; string keys declare child subcommand nodes.
2. **First-Class Combinators**: `c.group(...)` bundles reusable declarations; `c.inherit(...)` explicitly marks declarations visible to child subtrees.
3. **Cardinality Wrappers**: `c.optional()`, `c.required()`, and `c.repeated()` adjust cardinality algebraically without modifying the wrapped declaration kind.
4. **Zero Hidden State**: All constructors return pure Lua tables with explicit `_tag` discriminators.

---

## 2. Constructor Reference

### 2.1 Application & Topology

#### `c.create(config)`
Compiles and instantiates a Clingy application.
```lua
local app = c.create({
  name = "meteorite",
  version = "1.0.0",
  description = "Moonstone HTTP framework and CLI engine",
  c.root(c.node({
    c.inherit(c.flag("-v", "--verbose")),
    -- ...
  })),
})
```

#### `c.root(node_ast)`
Wraps the root node of the CLI application. Validates that the input is a valid `c.node(...)`.

#### `c.node(elements, metadata?)`
Declares a command node in the topology.
```lua
c.node({
  -- Numeric entries: declarations, modes, handlers
  c.flag("-f", "--force"),
  c.arg("source", v.string()),
  c.run(function(ctx) ... end),

  -- String entries: child subcommand nodes
  build = c.node({ ... }),
  deploy = c.node({ ... }),
}, {
  description = "Command description",
  aliases = { "b" },
})
```

---

### 2.2 Reusable Composition & Inheritance

#### `c.group(...)`
Flattens a list of declarations or child nodes into the parent node.
```lua
local logging_flags = c.group(
  c.flag("-q", "--quiet"),
  c.flag("-v", "--verbose"),
  c.option("--log-level", v.picklist({ "debug", "info", "warn", "error" }))
)

local my_cmd = c.node({
  logging_flags,
  c.arg("target", v.string()),
})
```

#### `c.inherit(...)`
Explicitly designates declarations to cascade downward to all descendant command segments.
```lua
c.node({
  c.inherit(
    c.flag("-v", "--verbose"),
    c.option("-c", "--config", v.string())
  ),
  subcommand = c.node({
    -- subcommand sees -v and -c without redeclaring them
  }),
})
```
*Note: Declaring positional arguments (`c.arg`) inside `c.inherit()` is rejected at compile time.*

---

### 2.3 Declarations: Flags, Options, Arguments, Passthrough

#### `c.flag(short_or_long, ...)`
Declares a boolean flag. Flags consume 0 values (`values = { min = 0, max = 0 }`) and default to `false`.
```lua
c.flag("-v", "--verbose")
c.flag("--json")
c.flag("-f")
```

#### `c.option(short_or_long, ..., schema?, opts?)`
Declares an option that consumes 1 string value from argv and adapts/validates it.
```lua
c.option("-c", "--config", v.string())
c.option("-p", "--port", v.integer())
c.option("-e", "--env", v.picklist({ "dev", "prod" }), { default = "dev" })
```

#### `c.arg(name, schema?, opts?)`
Declares a positional CLI argument.
```lua
c.arg("filename", v.string())
c.arg("port", v.integer(), { default = 8080 })
```

#### `c.passthrough(result_key)`
Captures all raw tokens following the `--` delimiter into `ctx.args[result_key]` as an array of raw strings.
```lua
c.passthrough("cargo_args")
```

---

### 2.4 Cardinality Modifiers

Clingy provides algebraic cardinality modifiers that wrap declarations:

```lua
-- Optional argument (0..1)
c.optional(c.arg("output_dir", v.string()))

-- Explicitly required option (1..1)
c.required(c.option("-e", "--environment", v.string()))

-- Repeated option (0..inf) -> aggregated as array in ctx.args
c.repeated(c.option("-D", "--define", v.string()))

-- Repeated positional argument (1..inf) -> must be final positional
c.repeated(c.arg("files", v.string()))
```

---

### 2.5 Parser Policies & Capabilities

#### `c.interspersed()` *(Default)*
Allows options and flags to appear anywhere between positional arguments within the segment.

#### `c.leading()`
Requires all options and flags to precede positional arguments within the segment. Once a positional argument is encountered, option recognition ceases.

#### `c.ordered()`
Enforces strict pipeline declaration order: arguments and options must appear in the exact order declared on the node.

#### `c.short_clusters()`
Enables POSIX single-dash flag clustering (e.g. `-xvf` expands to `-x -v -f`). Non-flag options with values cannot be clustered.

---

### 2.6 Execution Handlers & Lifecycle

#### `c.run(fn)`
Attaches an execution handler to the command node:
```lua
c.run(function(ctx)
  ctx.composer:log("info", "Starting application in " .. ctx.args.env)
  return 0
end)
```

#### `c.signals(policy_table)`
Declares signal handling callbacks for the node:
```lua
c.signals({
  interrupt = function(ctx)
    ctx.composer:log("warn", "SIGINT received! Aborting gracefully...")
  end,
  terminate = function(ctx)
    ctx.composer:log("warn", "SIGTERM received! Shutting down...")
  end,
})
```
