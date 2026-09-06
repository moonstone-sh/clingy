--[[
  src/clingy/completion/backends/fish.lua
  Fish shell completion integration and candidate renderer.
]]

local M = {}

---Generates the fish completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  return string.format([=[
function __%s_complete
    set -l cmd (commandline -cop)
    set -l cword (count $cmd)
    if test (count $cmd) -gt 0; and test (string length -- (commandline -ct)) -eq 0
        set cword (math $cword + 1)
    end
    %s --__clingy-complete fish $cmd --cword=$cword 2>/dev/null
end

complete -c %s -f -a '(__%s_complete)'
]=], app_name, cmd_path, app_name, app_name)
end

---Renders a CompletionResponse into tab-separated output lines for fish.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  local lines = {}
  for _, cand in ipairs(resp.candidates or {}) do
    if cand.description and cand.description ~= "" then
      table.insert(lines, cand.value .. "\t" .. cand.description)
    else
      table.insert(lines, cand.value)
    end
  end
  return table.concat(lines, "\n")
end

return M
