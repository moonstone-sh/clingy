--[[
  src/clingy/completion/backends/zsh.lua
  Zsh shell completion integration and candidate renderer.
]]

local response = require("clingy.completion.response")

local M = {}

---Generates the zsh completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  return string.format([=[
#compdef %s

__%s_complete() {
    local -a raw_output
    local -a candidates

    raw_output=("${(@f)$(%s --__clingy-complete zsh "${words[@]}" --cword="$CURRENT" 2>/dev/null)}")
    if [[ $? -ne 0 ]]; then
        return
    fi

    local has_files=0
    local has_dirs=0
    local has_nospace=0

    for line in "${raw_output[@]}"; do
        if [[ "$line" == :directive:* ]]; then
            local dir="${line#:directive:}"
            [[ "$dir" == *"filenames"* ]] && has_files=1
            [[ "$dir" == *"dirnames"* ]] && has_dirs=1
            [[ "$dir" == *"nospace"* ]] && has_nospace=1
        elif [[ -n "$line" ]]; then
            candidates+=("$line")
        fi
    done

    if [[ $has_nospace -eq 1 ]]; then
        compstate[insert]='0'
    fi

    if [[ ${#candidates[@]} -gt 0 ]]; then
        _describe -t commands '%s' candidates
    fi

    if [[ $has_files -eq 1 ]]; then
        _files
    elif [[ $has_dirs -eq 1 ]]; then
        _files -/
    fi
}

__%s_complete "$@"
]=], app_name, app_name, cmd_path, app_name, app_name)
end

---Renders a CompletionResponse into formatted output lines for zsh.
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
    if cand.description and cand.description ~= "" then
      local safe_desc = cand.description:gsub(":", "\\:")
      table.insert(lines, cand.value .. ":" .. safe_desc)
    else
      table.insert(lines, cand.value)
    end
  end

  return table.concat(lines, "\n")
end

return M
