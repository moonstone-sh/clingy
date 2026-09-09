#!/usr/bin/env bash
set -euo pipefail

moon exec ballad play tests/fixtures/packaged-cli/partiture.lua

archive="dist/registry/clingy-example/clingy-example-0.3.0-any.tar.gz"
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
  moon add local:moonstone/clingy-example@0.3.0 --bin
)

export PATH="$project/.moonstone/env/bin:$PATH"
cli="$project/.moonstone/env/bin/clingy-example"
test -x "$cli"
test "$("$cli" greet Clingy)" = "hello Clingy"

raw_completion="$("$cli" --__clingy-complete bash clingy-example "" --cword=2)"
grep -qx 'completion' <<<"$raw_completion"
grep -qx 'greet' <<<"$raw_completion"

completion_file="$project/clingy-example.bash"
"$cli" completion bash >"$completion_file"
source "$completion_file"
COMP_WORDS=(clingy-example "")
COMP_CWORD=1
COMPREPLY=()
__clingy-example_complete
printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'completion'
printf '%s\n' "${COMPREPLY[@]}" | grep -qx 'greet'
