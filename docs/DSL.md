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

### 2.3 Declarations: Flags, Options, Arguments, Composed Tokens, Passthrough

#### `c.flag(result_key?, short_or_long, ...)`
Declares a boolean flag. Flags consume 0 values (`values = { min = 0, max = 0 }`) and default to `false`.
```lua
c.flag("-v", "--verbose")
c.flag("--json")
c.flag("-f")

-- Explicit result key; ctx.args.dry_run is independent of the aliases.
c.flag("dry_run", "--dry-run", "-n")
```

#### `c.option(result_key?, short_or_long, ..., schema?)`
Declares an option that consumes 1 string value from argv and adapts/validates it.
```lua
c.option("-c", "--config", v.string())
c.option("-p", "--port", v.integer())

-- Explicit result key; the schema remains the final non-name argument.
c.option("config_file", "--config", "-c", v.string())
```

The canonical explicit form puts the result key first, followed by aliases and
at most one final schema. Aliases continue to be strings beginning with `-`.
Alias-only declarations retain their legacy schema placement, including a
schema before aliases, and continue to derive their result key from the longest
long alias.

#### `c.label(name, declaration)`
Assigns the handler-facing key compositionally. It may wrap one `c.arg`,
`c.option`, or `c.flag` exactly once. Labels must contain non-whitespace text.

```lua
local output = c.label("output", c.option("--output", "-o", v.string()))
local verbose = c.label("verbose", c.flag("--verbose", "-v"))
-- ctx:get(output), ctx.args.output, and ctx.args.verbose
```

#### `c.separator(separators, option, opts?)`
Controls the value spellings accepted by an option. `" "` means the following
argv token; punctuation is attached to the option spelling. `""` means an
adjacent value, such as `-Dname=value`; it is valid only for value-taking
options. Attached values are trimmed by default (including spaces/newlines);
use `{ trim = false }` to keep the exact substring.

```lua
c.separator({ "=", ":", " " }, c.option("--format", v.string()))
-- --format=json, --format:json, and --format json
```

#### `c.compose(...)`: one token, multiple typed fields
`c.compose` declares one required positional argv token whose **entire** text
must satisfy a fixed sequence of labelled captures, exact literals, and
separators. It is intentionally a node-local positional declaration, not a
global `:`/`=` splitting rule.

```lua
c.node({
  c.compose(
    c.label("environment", c.capture(v.string())),
    c.separator(":"),
    c.literal("database"),
    c.separator("="),
    c.label("database", c.capture(v.boolean()))
  ),
  c.run(function(ctx)
    -- run dev:database=true
    assert(ctx.args.environment == "dev")
    assert(ctx.args.database == true)
  end),
})
```

`c.capture(schema)` supplies the same lexical adaptation and Standard Schema
validation used by `c.arg` and `c.option`; every capture must be wrapped once
by `c.label(name, ...)`. `c.literal(text)` is exact. In this form,
`c.separator(text, opts?)` is a pattern fragment (the existing
`c.separator(separators, option, opts?)` option wrapper is unchanged).
Separators consume surrounding spaces and newlines by default. Use
`c.separator(":", { trim = false })` to preserve that whitespace as part of
an adjacent capture.

Patterns are anchored to the full argv token. To make boundaries explicit,
two captures may not be adjacent: put a non-empty literal or separator between
them. Compilation rejects empty/duplicate labels, unlabelled captures,
adjacent-capture ambiguity, output-key collisions, and `c.inherit(c.compose(...))`.
Composed tokens are fixed one-token positionals, so cardinality wrappers and
capture-level completions are intentionally unsupported; shell completion
suppresses candidates while the token is in focus.

#### `c.tail(name, terminator, { c.forward(mode) })`
Ends Clingy's grammar at a declared marker and forwards the remaining argv
tokens into `ctx.args[name]`. `trimmed` excludes the terminator; `complete`
includes it.

```lua
c.tail("forwarded", "--", { c.forward("trimmed") })
```

`c["end"](...)` remains available as a deprecated compatibility alias.

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
   ctx.presentation:log("info", "Starting application in " .. ctx.args.env)
  return 0
end)
```

#### `c.signals(policy_table)`
Declares signal handling callbacks for the node:
```lua
c.signals({
  interrupt = function(ctx)
     ctx.presentation:log("warn", "SIGINT received! Aborting gracefully...")
  end,
  terminate = function(ctx)
     ctx.presentation:log("warn", "SIGTERM received! Shutting down...")
  end,
})
```
