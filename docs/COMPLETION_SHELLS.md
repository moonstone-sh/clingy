# Shell completion

Clingy generates completion bridges for Bash, Zsh, Fish, and PowerShell. The
bridge sends the shell's argv view and active 1-based word index to the hidden
completion endpoint, then adapts typed response records to that shell.

```lua
completion = c.node({
  c.arg({ key = "shell", schema = v.picklist({ "bash", "zsh", "fish", "powershell" }) }),
  c.run(function(ctx)
    io.write(ctx.app:completion_script(ctx.args.shell, "mycli"), "\n")
  end),
})
```

Install the generated bridge with the normal mechanism for the target shell:

```bash
# Bash
mycli completion bash > ~/.local/share/bash-completion/completions/mycli

# Zsh: put _mycli in a directory on fpath, before compinit
mycli completion zsh > ~/.zsh/completion/_mycli

# Fish
mycli completion fish > ~/.config/fish/completions/mycli.fish
```

```powershell
mycli completion powershell > "$HOME/.mycli-completion.ps1"
. "$HOME/.mycli-completion.ps1"
```

The adapters preserve `:` inside values, quote whitespace where required, and
normalize quoted preceding arguments before querying Clingy. Bash excludes `:`
and `=` from its word-break reconstruction. PowerShell uses the active
`CommandAst` and cursor position rather than splitting command text.

Filesystem providers delegate enumeration to the active shell. `c.path()`
accepts files and directories, `c.file()` accepts files and traversal
directories, and `c.directory()` accepts directories. File suffix filters are
portable:

```lua
c.arg({
  key = "source",
  schema = v.string(),
  complete = c.file({ extensions = { "lua", "luax" } }),
})
```

Directories remain visible while completing a filtered file so the user can
continue traversing. A form or attached option may own only a suffix of the
active word; the bridge preserves its already-matched prefix:

```text
mycli --config=src/ma<TAB>       -> --config=src/main.lua
mycli argument:src/ma<TAB>      -> argument:src/main.lua
```

`c.none()` disables filename fallback. Dynamic and finite-value providers use
the same typed candidate records on every shell.

## Compatibility contract

| Feature | Bash | Zsh | Fish | PowerShell |
|---|---:|---:|---:|---:|
| Values, flags, and subcommands | Yes | Yes | Yes | Yes |
| Candidate descriptions | No | Yes | Yes | Yes |
| Colon and whitespace candidates | Yes | Yes | Yes | Yes |
| Files and directories | Yes | Yes | Yes | Yes |
| `c.file({ extensions = ... })` | Yes | Yes | Yes | Yes |
| Attached/form prefix preservation | Yes | Yes | Yes | Yes |
| Multi-word form traversal | Engine | Engine | Engine | Engine |

The release gate installs a packaged CLI with its declared Lua interpreter and
executes chained completion through Bash, Zsh, Fish, and PowerShell. See
`tests/packaged-completion.sh`.
