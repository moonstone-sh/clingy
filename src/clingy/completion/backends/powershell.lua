--[[
  src/clingy/completion/backends/powershell.lua
  PowerShell completion integration and candidate renderer.
]]

local M = {}

---Generates the PowerShell completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  return string.format([=[
Register-ArgumentCompleter -Native -CommandName '%s' -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $words = @($commandAst.Tokens | Where-Object { $_.Type -ne [System.Management.Automation.Language.TokenType]::EndOfInput } | ForEach-Object { $_.Text })
    $cword = $words.Count

    $raw = & "%s" --__clingy-complete powershell $words --cword=$cword 2>$null
    if ($null -eq $raw) { return }

    foreach ($line in $raw) {
        if ($line -match "^:directive:") { continue }
        $parts = $line -split "`t", 2
        $val = $parts[0]
        $desc = if ($parts.Count -gt 1) { $parts[1] } else { $val }
        [System.Management.Automation.CompletionResult]::new($val, $val, 'ParameterValue', $desc)
    }
}
]=], app_name, cmd_path)
end

---Renders a CompletionResponse into formatted lines for PowerShell.
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
