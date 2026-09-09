# Clingy Shell Completion Setup & Integration Guide

## 1. Overview

Clingy provides automatic completion script generation for four major shells:
- **Bash** (v4.0+)
- **Zsh** (v5.0+)
- **Fish** (v3.0+)
- **PowerShell** (v7.0+ / Windows PowerShell 5.1)

Completion scripts operate as thin, lightning-fast bridge wrappers around the binary's hidden `--__clingy-complete` endpoint.

---

## 2. Generating Completion Scripts

Applications built with Clingy can generate completion scripts programmatically or via a CLI subcommand:

```lua
local c = require("clingy")

local app = c.create({
  name = "mycli",
  version = "1.0.0",
  root = c.root(c.node({
    -- Subcommand: mycli completion <shell>
    completion = c.node({
      c.arg({ key = "shell" }),
      c.run(function(ctx)
        local script = ctx.app:completion_script(ctx.args.shell, "mycli")
        print(script)
      end),
    }),
  })),
})

app:run()
```

---

## 3. Shell Installation & Integration

### 3.1. Bash

#### Dynamic Eval in `~/.bashrc`
```bash
eval "$(mycli completion bash)"
```

#### Static File Installation
```bash
mycli completion bash > /etc/bash_completion.d/mycli
# or for per-user installation:
mycli completion bash > ~/.local/share/bash-completion/completions/mycli
```

#### Script Architecture
The Bash completion script registers a function using `complete -F _clingy_mycli -o default mycli`:
```bash
_clingy_mycli() {
  local cur prev words cword
  _init_completion -n = 2>/dev/null || {
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword=$COMP_CWORD
  }

  local out
  out="$(mycli --__clingy-complete --shell=bash --index="$((cword + 1))" -- "${words[@]}")"
  local status=$?
  if [ $status -ne 0 ]; then
    return $status
  fi

  local lines=()
  while IFS= read -r line; do
    if [[ "$line" == :directive:* ]]; then
      case "$line" in
        :directive:filenames) compopt -o filenames ;;
        :directive:nospace)   compopt -o nospace ;;
        :directive:dirnames)  compopt -o dirnames ;;
        :directive:nofiles)   compopt +o default ;;
      esac
    elif [ -n "$line" ]; then
      lines+=("$line")
    fi
  done <<< "$out"

  COMPREPLY=($(compgen -W "${lines[*]}" -- "$cur"))
}
complete -F _clingy_mycli -o default mycli
```

---

### 3.2. Zsh

#### Dynamic Eval in `~/.zshrc`
```zsh
eval "$(mycli completion zsh)"
```

#### Static File Installation (autoloaded via `fpath`)
```zsh
# Save to an fpath directory as _mycli:
mycli completion zsh > ~/.zsh/completion/_mycli

# Ensure ~/.zsh/completion is in your fpath before compinit in ~/.zshrc:
fpath=(~/.zsh/completion $fpath)
autoload -Uz compinit && compinit
```

#### Script Architecture
The Zsh completion script defines a `#compdef` function that extracts candidates and descriptions for `compadd`:
```zsh
#compdef mycli

_clingy_mycli() {
  local -a completions
  local -a completions_with_descriptions
  local response
  local directive_filenames=0
  local directive_nospace=0

  response=("${(@f)$(mycli --__clingy-complete --shell=zsh --index="$CURRENT" -- "${words[@]}")}")

  for line in "${response[@]}"; do
    if [[ "$line" == :directive:* ]]; then
      case "$line" in
        :directive:filenames) directive_filenames=1 ;;
        :directive:nospace)   directive_nospace=1 ;;
      esac
    elif [[ -n "$line" ]]; then
      if [[ "$line" =~ ":" ]]; then
        completions_with_descriptions+=("$line")
      else
        completions+=("$line")
      fi
    fi
  done

  if [ ${#completions_with_descriptions[@]} -gt 0 ]; then
    _describe -t commands "mycli" completions_with_descriptions
  fi
  if [ ${#completions[@]} -gt 0 ]; then
    compadd -a completions
  fi
  if [ $directive_filenames -eq 1 ]; then
    _files
  fi
}

_clingy_mycli "$@"
```

---

### 3.3. Fish

#### Installation
Save the completion script to Fish's completions directory:
```fish
mycli completion fish > ~/.config/fish/completions/mycli.fish
```

#### Script Architecture
Fish uses a one-line completion registration invoking the hidden endpoint dynamically:
```fish
function __clingy_mycli_complete
  set -l tokens (commandline -cop)
  set -l current (commandline -ct)
  set -l cursor (commandline -C)
  set -l words (commandline -o)
  set -l index (count $tokens)

  mycli --__clingy-complete --shell=fish --index=(math $index + 1) -- $words
end

complete -c mycli -f -a '(__clingy_mycli_complete)'
```

---

### 3.4. PowerShell

#### Dynamic Eval in `$PROFILE`
```powershell
Invoke-Expression (& mycli completion powershell | Out-String)
```

#### Static File Installation
Save the output into a script and dot-source it from `$PROFILE`:
```powershell
mycli completion powershell > "$HOME/.mycli-completion.ps1"
# In $PROFILE:
. "$HOME/.mycli-completion.ps1"
```

#### Script Architecture
PowerShell uses `Register-ArgumentCompleter -Native`:
```powershell
Register-ArgumentCompleter -Native -CommandName 'mycli' -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)

  $elements = $commandAst.ToString().Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
  $index = $elements.Count

  $output = & mycli --__clingy-complete --shell=powershell --index=$index -- $elements

  foreach ($line in $output) {
    if (-not [string]::IsNullOrWhiteSpace($line)) {
      $parts = $line.Split("`t", 2)
      $val = $parts[0]
      $desc = if ($parts.Length -gt 1) { $parts[1] } else { $val }
      [System.Management.Automation.CompletionResult]::new($val, $val, 'ParameterValue', $desc)
    }
  }
}
```

---

## 4. Shell Compatibility Matrix

| Feature | Bash | Zsh | Fish | PowerShell |
|---|---|---|---|---|
| Subcommand suggestions | Yes | Yes | Yes | Yes |
| Flag & option suggestions | Yes | Yes | Yes | Yes |
| Candidate descriptions | No (OS native) | Yes | Yes | Yes (ToolTips) |
| Dynamic context inspection | Yes | Yes | Yes | Yes |
| File fallback (`c.file`) | Yes | Yes | Yes | Yes |
| Directory fallback (`c.directory`) | Yes | Yes | Yes | Yes |
| Inline `--opt=val` completion | Yes | Yes | Yes | Yes |
| Passthrough suppression (`--`) | Yes | Yes | Yes | Yes |
