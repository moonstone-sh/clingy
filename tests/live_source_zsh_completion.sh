#!/usr/bin/env bash
set -euo pipefail

# Test: the zsh completion script generated directly from clingy's LIVE
# `src/` (no packaging, no registry, no locked dependency involved) produces
# real candidates without leaking internal parsing state.
#
# tests/packaged-completion.sh's zsh coverage exercises a REGISTRY-INSTALLED
# `clingy-example`, which resolves `require("clingy")` through this
# project's own locked `moonstone/clingy` dependency (self-referential, a
# dev/bootstrap pin) -- so it only ever verifies whatever clingy version
# happens to already be locked and published, never this repo's own
# in-progress fix. This test instead runs
# tests/fixtures/packaged-cli/main.lua directly against `src/` via LUA_PATH,
# so it verifies the code actually under test.
#
# Regression covered: a real zsh completion function whose raw-output has 2+
# lines in one call (root-level completion here: a V header plus one C
# record per subcommand) runs its per-record parsing loop more than once.
# If that loop's `local record value description fourth fifth` line sits
# INSIDE the loop, zsh treats the second-and-later bare re-declaration of an
# already-local variable as a listing query and prints "name=value" straight
# to stdout instead of resetting it -- leaking "record=...\nvalue=..." lines
# into the real candidate output.

if ! command -v zsh >/dev/null 2>&1; then
  echo "⚠ zsh not available, skipping live_source_zsh_completion.sh" >&2
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PROJECT_ROOT}"

fixture_dir="$(mktemp -d /tmp/clingy-live-source-completion.XXXXXX)"
trap 'rm -rf "${fixture_dir}"' EXIT

# `require("clingy")` must resolve to this repo's live `src/`, ahead of
# anything materialized under `.moonstone/env/` for the locked dependency
# closure (`valua` etc. still need to come from there). Lua 5.4 prefers a
# version-specific LUA_PATH_5_4 over the generic LUA_PATH when both are
# set, and `moon run` sets LUA_PATH_5_4 for this project's own locked
# environment -- unset it (matching packaged-completion.sh's own launcher-
# isolation note) or it silently wins and this test exercises the locked
# dependency instead of live src.
unset LUA_PATH_5_4 LUA_CPATH_5_4
export LUA_PATH="./src/?.lua;./src/?/init.lua;./?.lua;./?/init.lua;./.moonstone/env/share/lua/5.4/?.lua;./.moonstone/env/share/lua/5.4/?/init.lua;;"

lua_bin="$(command -v lua || command -v luajit)"
test -n "${lua_bin}"

# A shim on PATH named exactly "clingy-example" -- the generated zsh
# function invokes the app by this bare name (main.lua hardcodes it as the
# `cmd_path` argument to `completion_script`), so a real subprocess lookup
# must find it.
cat > "${fixture_dir}/clingy-example" <<SH
#!/usr/bin/env sh
export LUA_PATH="${LUA_PATH}"
exec "${lua_bin}" "${PROJECT_ROOT}/tests/fixtures/packaged-cli/main.lua" "\$@"
SH
chmod +x "${fixture_dir}/clingy-example"
export PATH="${fixture_dir}:${PATH}"

zsh_completion_file="${fixture_dir}/clingy-example.zsh"
clingy-example completion zsh > "${zsh_completion_file}"

zsh_output="$(CLINGY_COMPLETION_FILE="${zsh_completion_file}" zsh -fc '
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
  words=(clingy-example "")
  CURRENT=2
  _clingy_636c696e67792d6578616d706c65
')"

grep -qx 'chain' <<<"${zsh_output}"
grep -qx 'greet' <<<"${zsh_output}"
grep -qx 'completion' <<<"${zsh_output}"
if grep -qE '^(record|value|description|fourth|fifth)=' <<<"${zsh_output}"; then
  echo "Zsh completion leaked internal parsing-variable state into candidate output:" >&2
  grep -E '^(record|value|description|fourth|fifth)=' <<<"${zsh_output}" >&2
  exit 1
fi

echo "━━━ ✓ live-source zsh completion (no state leakage) passed ━━━"
