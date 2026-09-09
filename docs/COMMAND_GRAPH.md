# Command graph

`c.create` compiles nested `c.node` values into a router. Numeric entries are
declarations; string keys are child commands.

```lua
c.root(c.node({
  c.inherit(c.flag({ key = "verbose", aliases = { "-v", "--verbose" } })),
  build = c.node({
    c.arg({ key = "target", schema = v.string() }),
    c.run(build),
  }),
}))
```

Each compiled binding records its owner, key, occurrence limits, schema, form,
separator policy, aggregation mode, and completion provider. Inherited named
bindings remain owned by the declaring node. Positional declarations cannot be
inherited.
