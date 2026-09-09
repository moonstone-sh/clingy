# Completion

Attach completion directly to any declaration or capture:

```lua
c.arg({ key = "input", schema = v.string(), complete = c.file() })
c.option({ key = "cwd", aliases = { "--cwd" }, complete = c.directory() })
c.capture({ key = "profile", schema = Profile, complete = c.values({ "dev", "prod" }) })
```

Available providers are `c.values`, `c.path`, `c.file`, `c.directory`,
`c.dynamic`, and `c.none`. Finite schema choices are discovered automatically.
Explicit `complete` metadata wins over schema discovery.

Form completion preserves matched literals, so completing `dev:a` can return
`dev:adam`. Captures following `c.next_token()` complete the next argv word.
Generate integration scripts with `app:completion_script(shell, command)`.
