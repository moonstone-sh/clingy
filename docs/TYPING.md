# Typing

Schemas validate captured strings and determine the values delivered through
`ctx.args`. Keys come from `key`, never from aliases.

```lua
local count = c.option({
  key = "count",
  aliases = { "-n", "--count" },
  value = { schema = v.integer() },
})
```

The handler sees `ctx.args.count` as `integer|nil`. A declaration with
`occurs.max = "many"` produces an array. Requiredness follows `occurs.min`.
Form captures keep their own schemas and are returned inside the declaration's
record.

LuaLS declarations live in `luals/library/clingy.lua` and mirror this table API.
