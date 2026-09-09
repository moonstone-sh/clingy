--[[
  src/clingy/completion/backends/bash.lua
  Bash shell completion integration and candidate renderer.
]]

local response = require("clingy.completion.response")

local M = {}

---Generates the bash completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  return string.format([=[
# bash completion for %s -*- shell-script -*-
__%s_complete() {
    local cur prev words cword
    if type _init_completion >/dev/null 2>&1; then
        _init_completion -n = 2>/dev/null
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi
    # Clingy's completion API uses Lua's 1-based word indices.
    cword=$((cword + 1))

    local output
    output=$(%s --__clingy-complete bash "${words[@]}" --cword="$cword" 2>/dev/null)
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        return $exit_code
    fi

    local IFS=$'\n'
    local lines
    read -d '' -ra lines <<< "$output" || true

    for line in "${lines[@]}"; do
        if [[ "$line" == :directive:* ]]; then
            local directive="${line#:directive:}"
            if [[ "$directive" == *"filenames"* ]]; then
                compopt -o filenames 2>/dev/null
            fi
            if [[ "$directive" == *"nospace"* ]]; then
                compopt -o nospace 2>/dev/null
            fi
            if [[ "$directive" == *"dirnames"* ]]; then
                compopt -o dirnames 2>/dev/null
            fi
        elif [[ -n "$line" ]]; then
            COMPREPLY+=("$line")
        fi
    done
}
complete -o default -F __%s_complete %s
]=], app_name, app_name, cmd_path, app_name, app_name)
end

---Renders a CompletionResponse into formatted output lines for bash.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  local lines = {}

  local dir_parts = {}
  if resp:has_directive(response.DIRECTIVE.FILENAMES) then
    table.insert(dir_parts, "filenames")
  end
  if resp:has_directive(response.DIRECTIVE.DIRECTORIES) then
    table.insert(dir_parts, "dirnames")
  end
  if resp:has_directive(response.DIRECTIVE.NO_SPACE) then
    table.insert(dir_parts, "nospace")
  end

  if #dir_parts > 0 then
    table.insert(lines, ":directive:" .. table.concat(dir_parts, ","))
  end

  for _, cand in ipairs(resp.candidates or {}) do
    table.insert(lines, cand.value)
  end

  return table.concat(lines, "\n")
end

return M
