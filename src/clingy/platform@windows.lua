-- The shell boundary is deliberately narrow. Native supervision uses a Job
-- Object; this synchronous boundary rejects cmd expansion rather than guessing.
local M = { windows = true, null = "NUL", executable_suffix = ".exe" }
function M.quote(value)
  assert(type(value) == "string", "Windows process value must be a string")
  assert(not value:find('[%%!&|<>^"\r\n%z()]'), "Windows shell value contains a cmd metacharacter; use a native task or a file")
  assert(value:sub(-1) ~= "\\", "Windows shell value ends in a backslash; use forward slashes")
  return '"' .. value .. '"'
end
function M.command(opts)
  local parts = { "setlocal DisableDelayedExpansion" }
  if opts.cwd then parts[#parts + 1] = "cd /d " .. M.quote(opts.cwd) end
  local keys = {}
  for key in pairs(opts.env or {}) do
    assert(type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$"), "invalid environment key")
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do parts[#parts + 1] = "set " .. M.quote(key .. "=" .. opts.env[key]) end
  local argv = {}
  for _, value in ipairs(opts.argv) do
    local quoted = M.quote(value) -- validate even tokens that need no quotes
    argv[#argv + 1] = value:match("^[%w_./:=+-]+$") and value or quoted
  end
  parts[#parts + 1] = table.concat(argv, " ")
  return 'cmd /d /v:off /s /c "' .. table.concat(parts, " && ") .. '"'
end
function M.mkdir(path)
  if path == "" or path == "." then return end
  local command = M.windows and ("if not exist " .. M.quote(path) .. " mkdir " .. M.quote(path)) or ("mkdir -p " .. M.quote(path))
  assert(require("clingy.compat").exit_status(os.execute(command)) == 0, "cannot create directory " .. path)
end
return M
