local alter = require("alter")
local jsonc = require("alter_jsonc")

local init = {}

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

local function exists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

local function parent(path)
  local p = path:match("^(.*)/[^/]+$")
  return p and p ~= "" and p or nil
end

local function find_project_root(start)
  local current = start
  while current do
    if exists(current .. "/moonstone.toml") then return current end
    current = parent(current)
  end
  return start
end

local function lua_ls_version(root)
  local env = read_file(root .. "/.moonstone/env/env.toml")
  if not env then return nil, "Moonstone environment not found; run 'moon sync' first" end
  local runtime = env:match("%[runtime%](.-)\n%[") or env:match("%[runtime%](.*)$")
  if not runtime then return nil, "Moonstone environment has no runtime table" end
  local name = runtime:match('name%s*=%s*"([^"]+)"')
  local version = runtime:match('version%s*=%s*"([^"]+)"')
  if name == "luajit" then return "LuaJIT", "5.1" end
  if name ~= "lua" then return nil, "Unsupported Moonstone runtime: " .. tostring(name) end
  local major, minor
  if version then major, minor = version:match("^(%d+)%.(%d+)") end
  if not major then return nil, "Could not determine the selected Lua version" end
  return "Lua " .. major .. "." .. minor, major .. "." .. minor
end

local function confirm(summary, yes)
  io.stdout:write(summary .. "\n")
  if yes then return true end
  io.stdout:write("Apply these changes? [y/N] ")
  local response = io.read("*l")
  return response == "y" or response == "Y" or response == "yes"
end

local function descriptor(lua_dir)
  return {
    name = "clingy",
    path = ".moonstone/env/share/lua/" .. lua_dir .. "/clingy/luals/plugin.lua",
    transport = "^0.1.0",
    contract = 1,
    text_edits = "insertions",
    args = {},
    priority = "last",
  }
end

local function set_runtime_version(config, version)
  local doc, err = alter.open(config, { backend = jsonc, create = true, default_text = "{}\n" })
  if not doc then return nil, err end
  local runtime = doc:at("runtime")
  local kind = runtime:kind()
  if kind ~= "none" and kind ~= "object" then
    return nil, alter.errors.conflict({ "runtime" }, "object", kind)
  end
  runtime:ensure_object():at("version"):set(version)
  return doc:commit()
end

---@param opts { yes?: boolean, cwd?: string }
---@return table|nil result
---@return string|table|nil err
function init.run(opts)
  opts = opts or {}
  local cwd = opts.cwd or os.getenv("PWD") or "."
  local root = find_project_root(cwd)
  local config = root .. "/.luarc.json"
  local runtime_version, lua_dir_or_err = lua_ls_version(root)
  if not runtime_version then return nil, lua_dir_or_err end

  local transport = require("luals_composer")
  local plugin = descriptor(lua_dir_or_err)
  local plan, plan_err = transport.plan({ root = root, plugin = plugin })
  if not plan then return nil, plan_err end

  local summary = table.concat({
    "Clingy will configure " .. config,
    "  runtime.version = " .. runtime_version,
    "  " .. plan.summary,
    "  registry = " .. plan.registry,
  }, "\n")
  if not confirm(summary, opts.yes) then return nil, "cancelled" end

  -- Updating runtime.version invalidates the first Composer snapshot. Re-plan
  -- after this independent editor setting is committed; Composer remains the
  -- sole writer of plugin activation and its managed sidecar.
  local runtime_result, runtime_err = set_runtime_version(config, runtime_version)
  if not runtime_result then return nil, runtime_err end
  plan, plan_err = transport.plan({ root = root, plugin = plugin })
  if not plan then return nil, plan_err end
  local result, commit_err = plan:commit()
  if not result then return nil, commit_err end
  result.changed = runtime_result.changed or result.changed
  result.runtime = runtime_version
  return result
end

return init
