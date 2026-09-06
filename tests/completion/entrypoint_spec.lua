--[[
  tests/completion/entrypoint_spec.lua
  Hidden Completion Entrypoint (--__clingy-complete):
  Verifies that shell completion invocations are intercepted immediately,
  completely bypassing Composer presentation, event bus emissions, and exiting 0 with raw output.
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Hidden Completion Entrypoint (--__clingy-complete)", function()

  local app = c.create({
    name = "pilot",
    c.root(c.node({
      c.inherit(c.flag("-v", "--verbose")),

      fly = c.node({
        c.option("-s", "--speed", v.picklist({ "subsonic", "transonic", "supersonic" })),
        c.complete(c.values("north", "south", "east", "west"), c.arg("heading")),
        c.run(function() end),
      }, { description = "Fly the aircraft" }),

      land = c.node({
        c.run(function() end),
      }, { description = "Land the aircraft" }),
    })),
  })

  it("intercepts --__clingy-complete bash, bypasses Composer, and outputs raw candidates", function()
    local captured = {}
    local fake_stdout = {
      write = function(self, str)
        table.insert(captured, str)
      end,
    }

    local code = app:run({
      "--__clingy-complete",
      "bash",
      "pilot",
      "fl",
      "--cword=2",
    }, { stdout = fake_stdout })

    assert.equal(code, 0, "exits with 0 status code")
    local output = table.concat(captured)
    assert.truthy(output:find("^fly\n") or output:find("\nfly\n") or output == "fly\n", "outputs raw 'fly'")
    -- Ensure Composer JSON / ANSI envelopes are completely absent
    assert.falsy(output:find('"protocol":'), "zero JSON envelopes")
    assert.falsy(output:find("\27%["), "zero ANSI escape codes")
  end)

  it("supports --cword separated by space as two tokens (--cword 3)", function()
    local captured = {}
    local fake_stdout = {
      write = function(self, str)
        table.insert(captured, str)
      end,
    }

    local code = app:run({
      "--__clingy-complete",
      "zsh",
      "pilot",
      "fly",
      "--speed",
      "",
      "--cword",
      "4",
    }, { stdout = fake_stdout })

    assert.equal(code, 0)
    local output = table.concat(captured)
    assert.truthy(output:find("subsonic"), "contains subsonic")
    assert.truthy(output:find("transonic"), "contains transonic")
    assert.truthy(output:find("supersonic"), "contains supersonic")
  end)

  it("renders zsh formatting with descriptions directly to stdout stream", function()
    local captured = {}
    local fake_stdout = {
      write = function(self, str)
        table.insert(captured, str)
      end,
    }

    local code = app:run({
      "--__clingy-complete",
      "zsh",
      "pilot",
      "",
      "--cword=2",
    }, { stdout = fake_stdout })

    assert.equal(code, 0)
    local output = table.concat(captured)
    assert.truthy(output:find("fly:Fly the aircraft"), "zsh format includes description")
    assert.truthy(output:find("land:Land the aircraft"), "zsh format includes description")
  end)

  it("fails silently and returns 0 exit code on malformed completion requests", function()
    local captured = {}
    local fake_stdout = {
      write = function(self, str)
        table.insert(captured, str)
      end,
    }

    -- Completely empty / invalid cword
    local code = nil
    assert.no_error(function()
      code = app:run({
        "--__clingy-complete",
        "bash",
      }, { stdout = fake_stdout })
    end)

    assert.equal(code, 0, "always exits 0 cleanly for shell completion harness")
  end)

end)
