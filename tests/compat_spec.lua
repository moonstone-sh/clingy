local h = require("tests.harness")
local compat = require("clingy.compat")
local process = require("clingy.process")

local describe, it = h.describe, h.it
local assert = h.assert

local posix = package.config:sub(1, 1) == "/"

describe("Lua-version compatibility (clingy.compat)", function()
  describe("to_integer", function()
    it("matches math.tointeger on every Lua", function()
      assert.equal(compat.to_integer(3), 3)
      assert.equal(compat.to_integer(-7), -7)
      assert.equal(compat.to_integer(4.0), 4)
      assert.equal(compat.to_integer(1.5), nil)
      assert.equal(compat.to_integer(0 / 0), nil)
      assert.equal(compat.to_integer(math.huge), nil)
      assert.equal(compat.to_integer(-math.huge), nil)
    end)
  end)

  describe("exit_status", function()
    it("normalizes the Lua 5.2+ shape", function()
      assert.equal(compat.exit_status(true, "exit", 0), 0)
      assert.equal(compat.exit_status(nil, "exit", 3), 3)
      assert.equal(compat.exit_status(nil, "signal", 2), 130)
    end)

    it("normalizes the Lua 5.1 / LuaJIT shape", function()
      assert.equal(compat.exit_status(0), 0)
      assert.equal(compat.exit_status(true), 0)
      if posix then
        assert.equal(compat.exit_status(768), 3)  -- wait status of `exit 3`
        assert.equal(compat.exit_status(2), 130)  -- killed by SIGINT
      end
    end)

    it("reports a child's exit code from os.execute on this interpreter", function()
      if not posix then return end
      assert.equal(compat.exit_status(os.execute("exit 3")), 3)
      assert.equal(compat.exit_status(os.execute("true")), 0)
    end)

    it("reports a child's exit code for inherit-mode processes", function()
      if not posix then return end
      local child = process.ManagedProcess.new({ argv = { "sh", "-c", "exit 3" }, mode = "inherit" })
      assert.equal(child:wait(), 3)
    end)
  end)
end)
