local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it, assert = h.describe, h.it, h.assert

describe("v0.3 table declarations and forms", function()
  it("parses attached, detached, and repeated named values", function()
    local app = c.create({ name = "tool", c.root(c.node({
      c.option({ key = "define", aliases = { "-D", "--define" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }),
    })) })
    local parsed = app:parse({ "-D=one", "--define", "two", "-v" })
    assert.same(parsed.args.define, { "one", "two" })
    assert.equal(parsed.args.verbose, true)
  end)

  it("rejects a repeated default option", function()
    local app = c.create({ name = "tool", c.root(c.node({
      c.option({ key = "output", aliases = { "-o", "--output" }, value = { schema = v.string() } }),
    })) })
    assert.has_error(function() app:parse({ "-o", "one", "-o", "two" }) end, "at most 1")
  end)

  it("validates only the selected form choice", function()
    local app = c.create({ name = "tool", c.root(c.node({
      c.arg({ key = "value", form = c.choice({
        c.sequence({ c.literal({ text = "i:" }), c.capture({ key = "item", schema = v.integer() }) }),
        c.sequence({ c.literal({ text = "s:" }), c.capture({ key = "item", schema = v.string() }) }),
      }) }),
    })) })
    assert.equal(app:parse({ "s:abc" }).args.value.item, "abc")
  end)

  it("completes an active form capture as a valid argv fragment", function()
    local app = c.create({ name = "tool", c.root(c.node({
      c.arg({ key = "dev", form = c.sequence({
        c.literal({ text = "dev:" }),
        c.capture({ key = "user", schema = v.picklist({ "adam", "alice" }) }),
      }) }),
    })) })
    local response = app:complete({ words = { "tool", "dev:a" }, cword = 2 })
    assert.equal(response.candidates[1].value, "dev:adam")
    assert.equal(response.candidates[2].value, "dev:alice")
  end)

  it("rejects malformed table aliases", function()
    assert.has_error(function()
      c.flag({ key = "bad", aliases = { "not-an-option" } })
    end, "not a usable option")
  end)
end)
