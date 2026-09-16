# Completion

Attach completion directly to any declaration or capture:

```lua
c.arg({ key = "input", schema = v.string(), complete = c.file() })
c.arg({ key = "module", schema = v.string(), complete = c.file({ extensions = { "lua", "luax" } }) })
c.option({ key = "cwd", aliases = { "--cwd" }, complete = c.directory() })
c.capture({ key = "profile", schema = Profile, complete = c.values({ "dev", "prod" }) })
```

Available providers are `c.values`, `c.path`, `c.file`, `c.directory`,
`c.dynamic`, and `c.none`. Finite schema choices are discovered automatically.
Explicit `complete` metadata wins over schema discovery.

Form completion preserves matched literals, so completing `dev:a` can return
`dev:adam`. Forms retain their completion position across any number of
`c.next_token()` boundaries and then advance to the following declaration.
Generate integration scripts with `app:completion_script(shell, command)`,
or let a user (or a caller like `moon exec`) get the same script from the
binary itself with no app-side wiring: every Clingy app already answers
`<binary> --__moonstone-complete-script <shell> [cmd_path]` for free. See
[COMPLETION_PROTOCOL.md](COMPLETION_PROTOCOL.md) for both hidden endpoints.
