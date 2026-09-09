# Clingy DSL

Clingy 0.3 uses table declarations. Every value has an explicit handler key.

```lua
c.flag({ key = "verbose", aliases = { "-v", "--verbose" } })
c.option({
  key = "output",
  aliases = { "-o", "--output" },
  value = { schema = v.string(), attached = { "=", ":" }, detached = true },
})
c.arg({ key = "source", schema = v.string() })
```

Cardinality belongs to the declaration:

```lua
c.arg({ key = "files", schema = v.string(), occurs = { min = 1, max = "many" } })
c.option({ key = "define", aliases = { "-D" }, occurs = { min = 0, max = "many" } })
```

Forms describe structured values. `c.sequence` composes atoms, `c.choice`
selects one branch, `c.optional` makes one form atom optional, and
`c.next_token()` moves the cursor to the next argv word.

```lua
c.arg({
  key = "development",
  occurs = { min = 0, max = "many" },
  form = c.sequence({
    c.literal({ text = "dev:" }),
    c.capture({ key = "user", schema = v.string() }),
    c.optional(c.sequence({
      c.literal({ text = "=" }),
      c.capture({ key = "enabled", schema = v.boolean() }),
    })),
  }),
})
```

See the repository README for the complete API map.
