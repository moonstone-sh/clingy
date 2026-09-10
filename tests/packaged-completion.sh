#!/usr/bin/env bash
set -euo pipefail

if [[ "${CLINGY_REQUIRE_ALL_SHELLS:-0}" == 1 ]]; then
  for required_shell in bash zsh fish pwsh; do
    command -v "$required_shell" >/dev/null 2>&1 || {
      echo "required completion shell is unavailable: $required_shell" >&2
      exit 1
    }
  done
fi

moon exec ballad play tests/fixtures/packaged-cli/partiture.lua

package_version="$(awk '
  /^\[package\]$/ { in_package = 1; next }
  /^\[/ { in_package = 0 }
  in_package && /^version = / {
    sub(/^version = "/, "")
    sub(/".*/, "")
    print
    exit
  }
' moonstone.toml)"
test -n "$package_version"

archive="dist/registry/clingy-example/clingy-example-${package_version}-any.tar.gz"
test -f "$archive"

fixture_dir="$(mktemp -d /tmp/clingy-packaged-completion.XXXXXX)"
trap 'rm -rf "$fixture_dir"' EXIT

export MOONSTONE_HOME="$fixture_dir/moonstone-home"
export MOONSTONE_CONFIG="$MOONSTONE_HOME/config"
export MOONSTONE_DATA="$MOONSTONE_HOME/data"
export MOONSTONE_CACHE="$MOONSTONE_HOME/cache"
export XDG_CONFIG_HOME="$MOONSTONE_HOME/xdg-config"
export XDG_DATA_HOME="$MOONSTONE_HOME/xdg-data"
export XDG_CACHE_HOME="$MOONSTONE_HOME/xdg-cache"
mkdir -p "$MOONSTONE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME"

registry="$fixture_dir/registry"
project="$fixture_dir/project"
project_name="completion-smoke-${fixture_dir##*.}"
moon registry create "$registry" local
moon registry push "$registry" \
  --descriptor dist/registry/clingy-example/package.toml \
  --blob "$archive"

(
  cd "$fixture_dir"
  moon init project --name "$project_name" --kind script \
    --interpreter lua@5.4 --no-git --empty --no-sync
)
(
  cd "$project"
  moon registry add --name local --url "$registry"
  moon add "local:moonstone/clingy-example@${package_version}" --bin
)

export PATH="$project/.moonstone/env/bin:$PATH"
# The exported launcher owns its Lua search path. Do not let the development
# project's versioned Lua variables shadow the package closure.
unset LUA_PATH LUA_CPATH LUA_PATH_5_4 LUA_CPATH_5_4
cli="$project/.moonstone/env/bin/clingy-example"
test -x "$cli"
test "$("$cli" greet Clingy)" = "hello Clingy"

raw_completion="$("$cli" --__clingy-complete bash clingy-example "" --cword=2)"
grep -qx $'V\t2' <<<"$raw_completion"
grep -qx $'C\tcompletion' <<<"$raw_completion"
grep -qx $'C\tgreet' <<<"$raw_completion"

completion_file="$project/clingy-example.bash"
"$cli" completion bash >"$completion_file"
source "$completion_file"
COMP_WORDS=(clingy-example "")
COMP_CWORD=1
COMPREPLY=()
__clingy_636c696e67792d6578616d706c65_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'completion'
printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'greet'

COMP_WORDS=(clingy-example chain --first-flag-completed argument:this)
COMP_CWORD=3
__clingy_636c696e67792d6578616d706c65_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'argument:thisgotcompletedtoo'

mkdir -p "$project/completed/path/from/suggestion/and"
touch "$project/completed/path/from/suggestion/and/extension.luax"
touch "$project/completed/path/from/suggestion/and/extension.lua"
(
  cd "$project"
  COMP_WORDS=(clingy-example chain --first-flag-completed argument:thisgotcompletedtoo completed/path/from/suggestion/and/extension.l)
  COMP_CWORD=4
  __clingy_636c696e67792d6578616d706c65_complete
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'completed/path/from/suggestion/and/extension.luax'
  if printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'completed/path/from/suggestion/and/extension.lua'; then
    echo "Bash completion ignored the luax extension filter" >&2
    exit 1
  fi
  COMP_WORDS=(clingy-example chain --config=completed/path/from/suggestion/and/extension.l)
  COMP_CWORD=2
  __clingy_636c696e67792d6578616d706c65_complete
  printf '%s\n' "${COMPREPLY[@]}" | grep -qx -- '--config=completed/path/from/suggestion/and/extension.luax'
)
echo "Bash packaged completion passed"

zsh_completion_file="$project/clingy-example.zsh"
"$cli" completion zsh >"$zsh_completion_file"
zsh_output="$(CLINGY_COMPLETION_FILE="$zsh_completion_file" zsh -fc '
  autoload -Uz compinit
  compinit -D
  source "$CLINGY_COMPLETION_FILE"
  compadd() {
    local value
    for value in "$@"; do
      [[ "$value" == -- || "$value" == -* ]] && continue
      print -r -- "$value"
    done
  }
  words=(clingy-example chain --first-flag-completed argument:this)
  CURRENT=4
  _clingy_636c696e67792d6578616d706c65
  words=(clingy-example chain --first-flag-completed argument:o)
  _clingy_636c696e67792d6578616d706c65
  words=(clingy-example chain --first-flag-completed argument:s)
  _clingy_636c696e67792d6578616d706c65
')"
grep -qx 'argument:thisgotcompletedtoo' <<<"$zsh_output"
grep -qx 'argument:other:value' <<<"$zsh_output"
grep -qx 'argument:sad pepe' <<<"$zsh_output"
echo "Zsh packaged completion passed"

if command -v fish >/dev/null 2>&1; then
  fish_completion_file="$project/clingy-example.fish"
  "$cli" completion fish >"$fish_completion_file"
  string_output="$(CLINGY_COMPLETION_FILE="$fish_completion_file" fish -c '
    source $CLINGY_COMPLETION_FILE
    complete -C "clingy-example chain --first-flag-completed argument:this"
  ')"
  # Fish may escape insertable whitespace, but punctuation remains part of the
  # candidate rather than protocol syntax.
  grep -q '^argument:thisgotcompletedtoo' <<<"$string_output"
  (
    cd "$project"
    CLINGY_COMPLETION_FILE="$fish_completion_file" fish -c '
      source $CLINGY_COMPLETION_FILE
      complete -C "clingy-example chain --first-flag-completed argument:thisgotcompletedtoo completed/path/from/suggestion/and/extension.l"
    '
  ) | grep -q '^completed/path/from/suggestion/and/extension.luax'
  echo "Fish packaged completion passed"
fi

if command -v pwsh >/dev/null 2>&1; then
  powershell_completion_file="$project/clingy-example.ps1"
  "$cli" completion powershell >"$powershell_completion_file"
  CLINGY_COMPLETION_FILE="$powershell_completion_file" pwsh -NoProfile -Command '
    . $env:CLINGY_COMPLETION_FILE
    $rootLine = "clingy-example "
    $rootMatches = (TabExpansion2 $rootLine $rootLine.Length).CompletionMatches
    if (-not ($rootMatches.ListItemText -contains "chain")) { Write-Output "PowerShell trailing-word completion failed"; $rootMatches | Format-List *; exit 1 }
    $line = "clingy-example chain --first-flag-completed argument:this"
    $matches = (TabExpansion2 $line $line.Length).CompletionMatches
    if (-not ($matches.ListItemText -contains "argument:thisgotcompletedtoo")) { Write-Output "PowerShell value completion failed"; $matches | Format-List *; exit 1 }
    $spaceLine = "clingy-example chain --first-flag-completed argument:s"
    $spaceMatches = (TabExpansion2 $spaceLine $spaceLine.Length).CompletionMatches
    $quotedSpace = [char]39 + "argument:sad pepe" + [char]39
    if (-not ($spaceMatches.CompletionText -contains $quotedSpace)) { Write-Output "PowerShell quoting failed"; $spaceMatches | Format-List *; exit 1 }
    $pathLine = "clingy-example chain --first-flag-completed `"argument:sad pepe`" completed/path/from/suggestion/and/extension.l"
    Set-Location (Split-Path $env:CLINGY_COMPLETION_FILE)
    $pathMatches = (TabExpansion2 $pathLine $pathLine.Length).CompletionMatches
    if (-not ($pathMatches.ListItemText -contains "completed/path/from/suggestion/and/extension.luax")) { Write-Output "PowerShell file completion failed"; $pathMatches | Format-List *; exit 1 }
    if ($pathMatches.ListItemText -contains "completed/path/from/suggestion/and/extension.lua") { Write-Output "PowerShell extension filter failed"; $pathMatches | Format-List *; exit 1 }
    $attachedLine = "clingy-example chain --config=completed/path/from/suggestion/and/extension.l"
    $attachedMatches = (TabExpansion2 $attachedLine $attachedLine.Length).CompletionMatches
    if (-not ($attachedMatches.ListItemText -contains "--config=completed/path/from/suggestion/and/extension.luax")) { Write-Output "PowerShell attached path completion failed"; $attachedMatches | Format-List *; exit 1 }
    exit 0
  '
  echo "PowerShell packaged completion passed"
fi
