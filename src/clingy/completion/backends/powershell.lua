--[[
  src/clingy/completion/backends/powershell.lua
  PowerShell completion integration and candidate renderer.
]]

local M = {}
local protocol = require("clingy.completion.protocol")

---Generates the PowerShell completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  local function ps_quote(value)
    return "'" .. tostring(value):gsub("'", "''") .. "'"
  end
  return string.format([=[
Register-ArgumentCompleter -Native -CommandName %s -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $words = [System.Collections.Generic.List[string]]::new()
    $elements = @($commandAst.CommandElements | Where-Object { $_.Extent.StartOffset -lt $cursorPosition })
    foreach ($element in $elements) {
        if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
            $words.Add([string]$element.Value)
        } else {
            $words.Add($element.Extent.Text)
        }
    }
    $relativeCursor = $cursorPosition - $commandAst.Extent.StartOffset
    $atBoundary = $cursorPosition -gt $commandAst.Extent.EndOffset -or
        ($relativeCursor -gt 0 -and $relativeCursor -le $commandAst.Extent.Text.Length -and
        [char]::IsWhiteSpace($commandAst.Extent.Text[$relativeCursor - 1]))
    if ($atBoundary) {
        $words.Add('')
    } elseif ($words.Count -eq 0) {
        $words.Add($wordToComplete)
    } else {
        $words[$words.Count - 1] = $wordToComplete
    }
    $cword = $words.Count

    $raw = & %s --__clingy-complete powershell $words --cword=$cword 2>$null
    if ($null -eq $raw) { return }

    $filesystem = '-'
    $replacePrefix = '-'
    $extensions = '-'
    foreach ($line in $raw) {
        $parts = $line -split "`t", 5
        if ($parts[0] -eq 'D') {
            $filesystem = $parts[2]
            $replacePrefix = $parts[3]
            $extensions = $parts[4]
            continue
        }
        if ($parts[0] -ne 'C') { continue }
        $val = $parts[1]
        $desc = if ($parts.Count -gt 2 -and $parts[2]) { $parts[2] } else { $val }
        $completionText = if ($val -match '[\s''"`$;&|<>(){}]') { "'" + $val.Replace("'", "''") + "'" } else { $val }
        [System.Management.Automation.CompletionResult]::new($completionText, $val, 'ParameterValue', $desc)
    }

    if ($filesystem -ne '-') {
        if ($replacePrefix -eq '-') { $replacePrefix = '' }
        $search = $wordToComplete
        if ($replacePrefix -and $search.StartsWith($replacePrefix, [System.StringComparison]::Ordinal)) {
            $search = $search.Substring($replacePrefix.Length)
        }
        $slash = [Math]::Max($search.LastIndexOf('/'), $search.LastIndexOf('\'))
        $directoryPart = if ($slash -ge 0) { $search.Substring(0, $slash + 1) } else { '' }
        $leaf = if ($slash -ge 0) { $search.Substring($slash + 1) } else { $search }
        $base = if ($directoryPart) { $directoryPart } else { '.' }
        $wanted = if ($extensions -eq '-') { @() } else { @($extensions -split ',') }
        Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | Where-Object {
            $_.Name.StartsWith($leaf, [System.StringComparison]::OrdinalIgnoreCase) -and
            ($filesystem -ne 'directory' -or $_.PSIsContainer) -and
            ($filesystem -ne 'file' -or $_.PSIsContainer -or $wanted.Count -eq 0 -or $wanted -contains $_.Extension.TrimStart('.'))
        } | Sort-Object Name | ForEach-Object {
            $value = $replacePrefix + $directoryPart + $_.Name
            if ($_.PSIsContainer) { $value += [IO.Path]::DirectorySeparatorChar }
            $completionText = if ($value -match '[\s''"`$;&|<>(){}]') { "'" + $value.Replace("'", "''") + "'" } else { $value }
            $kind = if ($_.PSIsContainer) { 'ProviderContainer' } else { 'ProviderItem' }
            [System.Management.Automation.CompletionResult]::new($completionText, $value, $kind, $_.FullName)
        }
    }
}
]=], ps_quote(app_name), ps_quote(cmd_path))
end

---Renders a CompletionResponse into formatted lines for PowerShell.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  return protocol.render(resp, true)
end

return M
