--[[
  src/clingy/completion/backends/fish.lua
  Fish shell completion integration and candidate renderer.
]]

local M = {}
local protocol = require("clingy.completion.protocol")

---Generates the fish completion script.
---@param app_name string
---@param cmd_path? string
---@return string
function M.script(app_name, cmd_path)
  cmd_path = cmd_path or app_name
  local function fish_quote(value)
    return "'" .. tostring(value):gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
  end
  local encoded_name = app_name:gsub(".", function(ch) return string.format("%02x", string.byte(ch)) end)
  local function_name = "__clingy_" .. encoded_name .. "_complete"
  return string.format([=[
function %s
    set -l cmd (commandline -cop)
    set -l cword (count $cmd)
    if test (count $cmd) -gt 0; and test (string length -- (commandline -ct)) -eq 0
        set cword (math $cword + 1)
    end
    set -l raw (%s --__clingy-complete fish $cmd --cword=$cword 2>/dev/null)
    set -l filesystem -
    set -l replace_prefix -
    set -l extensions -

    for line in $raw
        set -l fields (string split -m 4 \t -- $line)
        switch $fields[1]
            case C
                set -l description ''
                if test (count $fields) -ge 3
                    set description $fields[3]
                end
                printf '%%s\t%%s\n' $fields[2] $description
            case D
                set filesystem $fields[3]
                set replace_prefix $fields[4]
                set extensions $fields[5]
        end
    end

    if test "$filesystem" != -
        set -l current (commandline -ct)
        if test "$replace_prefix" = -
            set replace_prefix ''
        end
        set -l search $current
        if test -n "$replace_prefix"; and string match -q -- "$replace_prefix*" $search
            set search (string replace -- "$replace_prefix" '' $search)
        end

        set -l path_results
        if test "$filesystem" = directory
            set path_results (__fish_complete_directories $search)
        else
            set path_results (__fish_complete_path $search)
        end
        for item in $path_results
            set -l item_fields (string split -m 1 \t -- $item)
            set -l decoded (string unescape -- $item_fields[1])
            set -l allowed 1
            if test "$filesystem" = file; and test "$extensions" != -; and not test -d "$decoded"
                set allowed 0
                for extension in (string split , -- $extensions)
                    if string match -q -- "*.$extension" "$decoded"
                        set allowed 1
                    end
                end
            end
            if test $allowed -eq 1
                set -l completed (string escape -- "$replace_prefix$decoded")
                set -l description ''
                if test (count $item_fields) -ge 2
                    set description $item_fields[2]
                end
                printf '%%s\t%%s\n' $completed $description
            end
        end
    end
end

complete -c %s -f -a '(%s)'
]=], function_name, fish_quote(cmd_path), fish_quote(app_name), function_name)
end

---Renders a CompletionResponse into tab-separated output lines for fish.
---@param resp table CompletionResponse
---@return string
function M.render(resp)
  return protocol.render(resp, true)
end

return M
