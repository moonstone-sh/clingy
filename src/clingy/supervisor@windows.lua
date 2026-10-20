local M = { extension = ".ps1" }
local function literal(value)
  assert(type(value) == "string" and not value:find("\0", 1, true), "supervisor values must be strings without NUL")
  return "'" .. value:gsub("'", "''") .. "'"
end
function M.script(opts)
  assert(type(opts) == "table" and type(opts.argv) == "table" and #opts.argv > 0, "supervisor requires a nonempty argv")
  local grace = opts.grace_ms or 2000
  assert(type(grace) == "number" and grace % 1 == 0 and grace >= 0 and grace <= 60000, "supervisor grace_ms must be an integer between 0 and 60000")
  local argv, keys, env = {}, {}, {}
  for _, value in ipairs(opts.argv) do argv[#argv + 1] = literal(value) end
  for key in pairs(opts.env or {}) do
    assert(type(key) == "string" and key:match("^[A-Za-z_][A-Za-z0-9_]*$"), "invalid supervisor environment key")
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do env[#env + 1] = literal(key) .. "=" .. literal(opts.env[key]) end
  local cleanup = {}
  for _, path in ipairs(opts.cleanup_files or {}) do
    cleanup[#cleanup + 1] = literal(path)
  end
  return "$ErrorActionPreference='Stop'\n" ..
    "Add-Type -TypeDefinition @'\n" .. require("clingy.windows_job") .. "\n'@\n" ..
    "$code=[ClingyJob]::Run([string[]]@(" .. table.concat(argv, ",") .. ")," ..
    (opts.cwd and literal(opts.cwd) or "(Get-Location).Path") .. ",@{" .. table.concat(env, ";") .. "}," .. grace .. "," ..
    (opts.stdin_eof and "$true" or "$false") .. "," .. literal(opts.lock_dir or "") ..
    ",[string[]]@(" .. table.concat(cleanup, ",") .. "))\nexit $code\n"

end
function M.command(path)
  return "powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File " .. require("clingy.platform").quote(path)
end
return M
