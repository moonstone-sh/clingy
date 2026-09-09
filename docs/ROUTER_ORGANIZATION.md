# Router organization

Command nodes are ordinary Lua modules. A leaf module may return a declaration,
`c.group`, or `c.node`; the root imports and mounts it without a registration
phase.

```lua
-- cli/build.lua
return c.node({
  c.arg({ key = "target", schema = Target }),
  c.flag({ key = "release", aliases = { "-r", "--release" } }),
  c.run(run_build),
})
```

Use `c.group` for shared declarations and wrap the group with `c.inherit` only
when descendants should see those named bindings. Keep positional arguments on
their owning node.
