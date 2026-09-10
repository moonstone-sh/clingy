# Clingy

Clingy is a declarative Lua CLI engine. Commands declare their route, token grammar, and result shape; [Valua](https://github.com/moonstone-lua/valua) schemas validate and adapt captured text.

Every declaration has an explicit result key. Aliases never derive output names, and normal declarations do not use label wrappers.

## Quick start

```lua
local c = require("clingy")
local v = require("valua")

local app = c.create({
  name = "greet",
  c.root(c.node({
    c.flag({ key = "shout", aliases = { "-s", "--shout" } }),
    c.option({
      key = "greeting",
      aliases = { "-g", "--greeting" },
      value = { schema = v.string(), attached = { "=" }, detached = true },
    }),
    c.arg({ key = "name", schema = v.string() }),
    c.run(function(ctx)
      local name = ctx.args.shout and ctx.args.name:upper() or ctx.args.name
      ctx:log("info", string.format("%s, %s!", ctx.args.greeting or "Hello", name))
    end),
  })),
})

app:run(arg)
```

`greet --greeting=Hola Ada -s` sets `ctx.args.greeting` to `"Hola"` and `ctx.args.shout` to `true`. An absent flag is `false`; an absent optional value is `nil`.

## Declarations

`c.arg`, `c.option`, and `c.flag` differ in where parsing begins, not in how result keys are assigned.

```lua
c.arg({ key = "source", schema = v.string() })

c.option({
  key = "output",
  aliases = { "-o", "--output" },
  value = { schema = v.string(), attached = { "=" }, detached = true },
})

c.flag({ key = "verbose", aliases = { "-v", "--verbose" } })
```

Value policies are explicit. `attached` lists punctuation accepted between an alias and a value; `detached` consumes the next argv word; `adjacent = true` accepts forms such as `-Ipath`.

```lua
c.option({
  key = "include",
  aliases = { "-I", "--include" },
  value = {
    schema = v.string(),
    attached = { "=" },
    adjacent = true,
    detached = true,
  },
})
```

Use `occurs` for cardinality. `max = "many"` returns an array.

```lua
c.arg({
  key = "sources",
  schema = v.string(),
  occurs = { min = 1, max = "many" },
})
```

## Structured forms

A form describes a single value as an ordered argv grammar. `c.literal` consumes punctuation in the current word; `c.next_token()` crosses a word boundary. Captures are fields of the declaration result, never loose top-level arguments.

```lua
c.arg({
  key = "settings",
  occurs = { min = 0, max = "many" },
  form = c.sequence({
    c.capture({ key = "scope", schema = v.picklist({ "dev", "prod" }) }),
    c.literal({ text = ":" }),
    c.capture({ key = "name", schema = v.string() }),
    c.optional(c.sequence({
      c.literal({ text = "=" }),
      c.capture({ key = "value", schema = v.string() }),
    })),
  }),
})

c.arg({ key = "inherits", schema = v.string() })
```

```sh
tool dev:database=true dev:org="sad pepe" dev:user inherit
```

```lua
ctx.args.settings == {
  { scope = "dev", name = "database", value = "true" },
  { scope = "dev", name = "org", value = "sad pepe" },
  { scope = "dev", name = "user" },
}
ctx.args.inherits == "inherit"
```

The optional value is inline. Adding `c.next_token()` to that branch would consume `inherit` as `dev:user`’s value.

Use `c.choice` for distinct spellings instead of special-purpose declaration kinds:

```lua
c.sequence({
  c.capture({ key = "name", schema = v.string() }),
  c.choice({
    c.sequence({ c.literal({ text = "=" }), c.capture({ key = "value", schema = v.string() }) }),
    c.sequence({ c.next_token(), c.capture({ key = "value", schema = v.string() }) }),
  }),
})
```

That form expresses both `-Dname=value` and `-Dname value`; Clingy has no `c.define` primitive.

## Completion

Completion belongs on the declaration or capture that consumes the value. Picklist schemas and form literals also supply finite candidates automatically.

Completion does not validate an incomplete prefix. `tru` is invalid as a complete boolean but useful when completing `true`.

The completion subsystem is available as `c.completion`. It can query an app,
render a shell response, or generate an installation shim:

```lua
local response = c.completion.complete(app, {
  words = { "greet", "--g" },
  cword = 2,
})

local zsh = c.completion.render(response, "zsh")
local script = c.completion.completion_script(app, "zsh", "greet")
```

Its public provider constructors are `c.values`, `c.path`, `c.file`,
`c.directory`, `c.dynamic`, and `c.none`. Assign one to the `complete` field of
`c.arg`, `c.option`, `c.flag`, or `c.capture`.

`c.file({ extensions = { "lua", "luax" } })` applies the same suffix filter in
Bash, Zsh, Fish, and PowerShell. Filesystem completion also works after an
attached prefix such as `--config=` or a form literal such as `argument:`.

## API map

The public API is intentionally small enough to scan:

- App and graph: `c.create`, `c.reflect`, `c.inspect`, `c.compiler`, `c.parser`, `c.adapter`, `c.schema_adapter`.
- Router: `c.root`, `c.node`, `c.group`, `c.inherit`.
- Declarations: `c.arg`, `c.option`, `c.flag`.
- Forms: `c.sequence`, `c.choice`, `c.capture`, `c.literal`, `c.next_token`, `c.optional`.
- Parser policy: `c.interspersed`, `c.leading`, `c.ordered`, `c.short_clusters`, `c.passthrough`, `c.tail`, `c.forward`.
- Invocation: `c.run`, `c.signals`, `c.signal`, `c.stage`, `c.Context`.
- Completion: `c.completion`, `c.values`, `c.path`, `c.file`, `c.directory`, `c.dynamic`, `c.none`.
- Runtime and presentation: `c.scope`, `c.process`, `c.lifecycle`, `c.events`, `c.presentation`, `c.composer`, `c.null_host`, `c.recording_host`, `c.failing_host`, `c.help`, `c.format_version`, `c.util`.

An app exposes `graph`, `help`, `parse`, `run`, `handle_signal`, `complete`, and
`completion_script`. Handler contexts expose `get`, `scope`, `spawn`, `span`,
`progress`, `milestone`, `log`, `result`, `fail`, `confirm`, and `prompt`.
`c.completion` exposes `complete`, `render`, and `completion_script`, together
with its response, context, provider, discovery, partial-parser, and backend
modules.

`c.process.supervisor_script(opts)` generates an exec-able Bash supervisor for
a long-running, headless process group. It handles Ctrl-C, terminal Ctrl-D,
TERM, HUP, parent loss, bounded TERM-to-KILL escalation, and direct-child
reaping. See [foreground process supervision](docs/process-supervision.md) for
the ownership contract and platform limits. The older `ManagedProcess` API is
a synchronous command adapter; its state transitions are not native OS process
control.

## Commands and modes

Nodes compose into nested routers. Inherited declarations are visible to descendants; parser modes are local to a node.

```lua
c.root(c.node({
  c.inherit({ c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }) }),
  build = c.node({
    c.leading(),
    c.arg({ key = "source", schema = v.string() }),
    c.arg({ key = "destination", schema = v.string() }),
  }),
}))
```

`c.interspersed()` is the default. `c.leading()` stops option recognition after the first positional. `c.ordered()` enforces declaration order. `c.short_clusters()` enables transactional clusters such as `-xvf`.

A literal `--` ends option parsing. Use `c.tail` to capture or forward the remaining argv words.

## Documentation

- [Example projects](examples/README.md)
- [Command graph](docs/COMMAND_GRAPH.md)
- [Parsing semantics](docs/PARSING_SEMANTICS.md)
- [Runtime lifecycle](docs/RUNTIME_LIFECYCLE.md)
- [Output and events](docs/OUTPUT_AND_EVENTS.md)

## License

MIT.
