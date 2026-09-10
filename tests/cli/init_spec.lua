local h = require("tests.harness")
-- Monorepo development uses the sibling source tree until Composer is
-- published; released/CI environments resolve the declared Moonstone package.
package.path = "../luals-composer/src/?.lua;../luals-composer/src/?/init.lua;" .. package.path
local init = require("clingy.cli.init")

local describe, it = h.describe, h.it
local assert_true = h.assert.truthy
local assert_false = h.assert.falsy
local assert_equal = h.assert.equal

local function write(path, text)
  local f = assert(io.open(path, "wb"))
  f:write(text)
  f:close()
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local text = f:read("*a")
  f:close()
  return text
end

local function install_transport(root, lua_dir)
  lua_dir = lua_dir or "5.4"
  local path = root .. "/.moonstone/env/share/lua/" .. lua_dir .. "/luals_composer"
  assert(os.execute('mkdir -p "' .. path .. '"'))
  write(path .. "/init.lua", "return {}\n")
  write(path .. "/version.lua", [[return {
  PACKAGE = "moonstone/luals-composer",
  VERSION = "0.1.0",
  CONTRACT = 1,
  ENTRY_RELPATH = "luals_composer/init.lua",
}
]])
  local clingy = root .. "/.moonstone/env/share/lua/" .. lua_dir .. "/clingy/luals"
  assert(os.execute('mkdir -p "' .. clingy .. '"'))
  write(clingy .. "/plugin.lua", "return {}\n")
end

describe("Clingy Alter-backed LuaLS initialization", function()

  it("migrates a legacy plugin string, preserves comments, and is idempotent", function()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute('mkdir -p "' .. root .. '/.moonstone/env"'))
    write(root .. "/moonstone.toml", "[package]\nname = \"fixture\"\n")
    write(root .. "/.moonstone/env/env.toml", "[runtime]\nname = \"lua\"\nversion = \"5.4.9\"\nabi = \"lua54\"\n")
    install_transport(root)
    write(root .. "/other.lua", "return {}\n")
    write(root .. "/.luarc.json", "// retained\n{ \"runtime\": { \"plugin\": \"other.lua\" } }\n")

    local first = assert(init.run({ cwd = root, yes = true }))
    assert_true(first.changed)
    local text = read(root .. "/.luarc.json")
    assert_true(text:find("// retained", 1, true) ~= nil)
    assert_true(text:find('"Lua 5.4"', 1, true) ~= nil)
    assert_true(text:find("luals_composer/init.lua", 1, true) ~= nil)
    assert_true(text:find("pluginArgs", 1, true) ~= nil)
    assert_true(text:find("--config=luals-composer.json", 1, true) ~= nil)
    local registry = read(root .. "/luals-composer.json")
    assert_true(registry:find('"other.lua"', 1, true) ~= nil)
    assert_true(registry:find("clingy/luals/plugin.lua", 1, true) ~= nil)

    local second = assert(init.run({ cwd = root, yes = true }))
    assert_false(second.changed)
    assert_equal(read(root .. "/.luarc.json"), text)
    os.execute('rm -rf "' .. root .. '"')
  end)

  it("uses the Lua 5.1 package path for LuaJIT", function()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute('mkdir -p "' .. root .. '/.moonstone/env"'))
    write(root .. "/moonstone.toml", "[package]\nname = \"fixture\"\n")
    write(root .. "/.moonstone/env/env.toml", "[runtime]\nname = \"luajit\"\nversion = \"2.1.0\"\nabi = \"lua51\"\n")
    install_transport(root, "5.1")

    local result = assert(init.run({ cwd = root, yes = true }))
    assert_true(result.changed)
    assert_equal(result.runtime, "LuaJIT")
    assert_true(read(root .. "/luals-composer.json"):find(
      ".moonstone/env/share/lua/5.1/clingy/luals/plugin.lua", 1, true) ~= nil)
    os.execute('rm -rf "' .. root .. '"')
  end)

  it("refuses to write a broken transport configuration", function()
    local root = os.tmpname()
    os.remove(root)
    assert(os.execute('mkdir -p "' .. root .. '/.moonstone/env"'))
    write(root .. "/moonstone.toml", "[package]\nname = \"fixture\"\n")
    write(root .. "/.moonstone/env/env.toml", "[runtime]\nname = \"lua\"\nversion = \"5.4.9\"\nabi = \"lua54\"\n")

    local result, err = init.run({ cwd = root, yes = true })
    assert_false(result)
    assert_equal(err.code, "transport_missing")
    assert_true(err.message:find("Composer is not installed", 1, true) ~= nil)
    os.execute('rm -rf "' .. root .. '"')
  end)

end)
