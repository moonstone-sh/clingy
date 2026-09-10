# Command graph

`c.create` compiles `root = c.node(...)` into a router. Numeric entries are
declarations; string keys are child commands.

```lua
root = c.node({
  c.inherit(c.flag({ key = "verbose", aliases = { "-v", "--verbose" } })),
  build = c.node({
    c.arg({ key = "target", schema = v.string() }),
    c.run(build),
  }),
})
```

Each compiled binding records its owner, key, occurrence limits, schema, form,
separator policy, aggregation mode, and completion provider. Inherited named
bindings remain owned by the declaring node. Positional declarations cannot be
inherited.

At a node with child commands, positional declarations are an exact required
prefix. A child spelling before that prefix is an error, never positional data.
Once the prefix is complete, a primary child name or alias takes its edge.
`--` closes routing and allows an otherwise-reserved spelling to be consumed as
data. Optional and repeated positionals on a routing node are rejected because
they would make that branch point ambiguous.
