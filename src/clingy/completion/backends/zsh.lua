--[[
  src/clingy/completion/backends/zsh.lua
  Zsh shell completion integration and candidate renderer.
]]

local protocol = require("clingy.completion.protocol")

local M = {}

---Generates the zsh completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  local function shell_quote(value)
    return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
  end
  local encoded_name = app_name:gsub(".", function(ch) return string.format("%02x", string.byte(ch)) end)
  local function_name = "_clingy_" .. encoded_name
  return string.format([=[
#compdef %s

%s() {
    local -a raw_output
    local -a candidates
    local -a descriptions

    raw_output=("${(@f)$(%s --__clingy-complete zsh "${words[@]}" --cword="$CURRENT" 2>/dev/null)}")
    if [[ $? -ne 0 ]]; then
        return
    fi

    local has_files=0
    local has_dirs=0
    local has_nospace=0
    local filesystem="-"
    local replace_prefix="-"
    local extensions="-"

    for line in "${raw_output[@]}"; do
        local record value description fourth fifth
        IFS=$'\t' read -r record value description fourth fifth <<< "$line"
        if [[ "$record" == D ]]; then
            local dir="$value"
            filesystem="$description"
            replace_prefix="$fourth"
            extensions="$fifth"
            [[ "$dir" == *"filenames"* ]] && has_files=1
            [[ "$dir" == *"dirnames"* ]] && has_dirs=1
            [[ "$dir" == *"nospace"* ]] && has_nospace=1
        elif [[ "$record" == C ]]; then
            candidates+=("$value")
            descriptions+=("$description")
        fi
    done

    if [[ ${#candidates[@]} -gt 0 ]]; then
        if [[ $has_nospace -eq 1 ]]; then
            compadd -S '' -d descriptions -- "${candidates[@]}"
        else
            compadd -d descriptions -- "${candidates[@]}"
        fi
    fi

    if [[ "$replace_prefix" == - ]]; then replace_prefix=""; fi
    if [[ -n "$replace_prefix" ]]; then compset -P "${(b)replace_prefix}"; fi
    if [[ "$filesystem" == directory || $has_dirs -eq 1 ]]; then
        _files -/
    elif [[ "$filesystem" == file || "$filesystem" == path || $has_files -eq 1 ]]; then
        if [[ "$filesystem" == file && "$extensions" != - ]]; then
            local -a extension_parts
            extension_parts=("${(@s:,:)extensions}")
            local file_glob="*.(${(j:|:)extension_parts})(-.)"
            _files -g "$file_glob"
        else
            _files
        fi
    fi
}

compdef %s %s
]=], app_name, function_name, shell_quote(cmd_path), function_name, shell_quote(app_name))
end

---Renders a CompletionResponse into formatted output lines for zsh.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  return protocol.render(resp, true)
end

return M
