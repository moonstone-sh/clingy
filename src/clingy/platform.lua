local M = { windows = false, null = "/dev/null", executable_suffix = "" }
function M.quote(value)
  value = tostring(value)
  assert(not value:find("\0", 1, true), "process value contains NUL")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end
function M.command(opts)
  local parts, env = {}, {}
  if opts.cwd then parts[#parts + 1] = "cd " .. M.quote(opts.cwd) .. " &&" end
  for key, value in pairs(opts.env or {}) do
    assert(type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$"), "invalid environment key")
    env[#env + 1] = key .. "=" .. M.quote(value)
  end
  table.sort(env)
  for _, value in ipairs(env) do parts[#parts + 1] = value end
  for _, value in ipairs(opts.argv) do parts[#parts + 1] = M.quote(value) end
  return table.concat(parts, " ")
end
return M
