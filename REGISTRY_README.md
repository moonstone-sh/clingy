# Clingy

Clingy is a declarative CLI engine for Lua. It packages command routing,
argv-aware value grammars, structured lifecycle management, and terminal or
machine-readable presentation behind one Moonstone dependency.

## Install

```sh
moon add moonstone/clingy
moon exec clingy -- init --yes
```

`clingy init` enrolls the Clingy analyzer through
`moonstone/luals-composer`. Composer is the only component that writes
LuaLS plugin activation and composes Clingy with other enrolled plugins such
as Valua and Hydronium LUAX. The command manages the project-root
`.luarc.json`; it refuses ambiguous legacy plugin configurations instead of
guessing which arguments belong to which plugin.

The package is a portable Lua executable and library artifact. Moonstone locks
the exact artifact and selected runtime for the consuming project.

## Define a command

```lua
local c = require("clingy")
local v = require("valua")

local app = c.create({
  name = "deployer",
  version = "1.0.0",
  root = c.node({
    c.inherit({
      c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }),
      c.flag({ key = "json", aliases = { "--json" } }),
    }),

    deploy = c.node({
      c.arg({
        key = "environment",
        schema = v.picklist({ "development", "staging", "production" }),
      }),
      c.option({
        key = "tag",
        aliases = { "-t", "--tag" },
        value = { schema = v.string(), attached = { "=" }, detached = true },
      }),
      c.flag({ key = "dry_run", aliases = { "-d", "--dry-run" } }),

      c.run(function(ctx)
        return {
          environment = ctx.args.environment,
          tag = ctx.args.tag or "latest",
          dry_run = ctx.args.dry_run,
        }
      end),
    }),
  }),
})

app:run(arg)
```

All declarations use explicit keys. Alias spellings do not affect handler
field names.

## Structured argv values

Use a form when a value has internal structure. Captures become fields of the
declaration’s result record.

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
```

`dev:database=true dev:user` produces an array of records under
`ctx.args.settings`. `c.next_token()` is available when a grammar deliberately
consumes a detached value.

## What it provides

- `c.node`, `c.inherit`, `c.arg`, `c.option`, and `c.flag` for routing.
- `c.sequence`, `c.choice`, `c.literal`, `c.capture`, and `c.next_token` for value forms.
- `c.interspersed`, `c.leading`, `c.ordered`, and `c.short_clusters` for parser policy.
- Valua schema adaptation, declaration-local completion, structured scopes,
  subprocess supervision, signals, help, and NDJSON presentation.

Long-running tools can generate an exec-able Bash process-group owner with
`c.process.supervisor_script(opts)`. It provides terminal Ctrl-C/Ctrl-D
shutdown, bounded escalation, parent-loss cleanup, and session locking on
macOS/Linux; the repository documentation describes the exact contract.

See the repository [README](README.md) for the DSL overview and
[examples](examples/README.md) for runnable projects.
