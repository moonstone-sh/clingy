--[[
  src/clingy/completion/backends/bash.lua
  Bash shell completion integration and candidate renderer.
]]

local protocol = require("clingy.completion.protocol")

local M = {}

---Generates the bash completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
  end
  local encoded_name = app_name:gsub(".", function(ch) return string.format("%02x", string.byte(ch)) end)
  local function_name = "__clingy_" .. encoded_name .. "_complete"
  return string.format([=[
# bash completion for %s -*- shell-script -*-
%s() {
    local cur prev words cword
    if type _init_completion >/dev/null 2>&1 && _init_completion -n =: 2>/dev/null; then
        :
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
        words=("${COMP_WORDS[@]}")
        cword=$COMP_CWORD
    fi
    # Clingy's completion API uses Lua's 1-based word indices.
    cword=$((cword + 1))

    COMPREPLY=()
    local output
    output=$(%s --__clingy-complete bash "${words[@]}" --cword="$cword" 2>/dev/null)
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        return $exit_code
    fi

    local record first second third fourth
    local directive="-" filesystem="-" replace_prefix="-" extensions="-"
    while IFS=$'\t' read -r record first second third fourth; do
        if [[ "$record" == C ]]; then
            COMPREPLY+=("$first")
        elif [[ "$record" == D ]]; then
            directive="$first"
            filesystem="$second"
            replace_prefix="$third"
            extensions="$fourth"
        fi
    done <<< "$output"

    if [[ "$directive" != - || "$filesystem" != - ]]; then
        if [[ "$replace_prefix" == - ]]; then replace_prefix=""; fi
        if [[ "$extensions" == - ]]; then extensions=""; fi
        if [[ "$filesystem" != - ]]; then
            local search="$cur"
            if [[ -n "$replace_prefix" && "$search" == "$replace_prefix"* ]]; then
                search="${search#"$replace_prefix"}"
            fi
            local -a paths
            local path ext allowed
            if [[ "$filesystem" == directory ]]; then
                while IFS= read -r path; do paths+=("$path"); done < <(compgen -d -- "$search")
            else
                while IFS= read -r path; do paths+=("$path"); done < <(compgen -f -- "$search")
            fi
            for path in "${paths[@]}"; do
                allowed=1
                if [[ "$filesystem" == file && ! -d "$path" && -n "$extensions" ]]; then
                    allowed=0
                    ext="${path##*.}"
                    local -a wanted
                    IFS=',' read -ra wanted <<< "$extensions"
                    local wanted_ext
                    for wanted_ext in "${wanted[@]}"; do
                        [[ "$ext" == "$wanted_ext" ]] && allowed=1
                    done
                fi
                if [[ $allowed -eq 1 ]]; then
                    if [[ -d "$path" ]]; then path="${path%%/}/"; fi
                    COMPREPLY+=("$replace_prefix$path")
                fi
            done
            compopt -o filenames 2>/dev/null || true
        fi

        if [[ "$directive" != - ]]; then
            if [[ "$directive" == *"filenames"* ]]; then
                compopt -o filenames 2>/dev/null || true
            fi
            if [[ "$directive" == *"nospace"* ]]; then
                compopt -o nospace 2>/dev/null || true
            fi
            if [[ "$directive" == *"dirnames"* ]]; then
                compopt -o dirnames 2>/dev/null || true
            fi
            if [[ "$directive" == *"nofiles"* ]]; then
                compopt +o default 2>/dev/null || true
            fi
        fi
    fi
}
complete -o default -F %s %s
]=], app_name, function_name, shell_quote(cmd_path), function_name, shell_quote(app_name))
end

---Renders a CompletionResponse into formatted output lines for bash.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  return protocol.render(resp, false)
end

return M
