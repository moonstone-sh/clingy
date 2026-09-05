local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 13: Compile-Time Rejection of Ambiguous Grammar", function()

  it("rejects non-final repeated positional arguments followed by another positional", function()
    assert.has_error(function()
      c.create({
        name = "test-non-final-rep",
        c.root(c.node({
          c.repeated(c.arg("first_rep", v.string())),
          c.arg("second_fixed", v.string()),
        })),
      })
    end, "Non-final repeated positional 'first_rep' followed by positional 'second_fixed'")
  end)

  it("allows repeated positional argument when it is the final positional argument", function()
    local ok, app = pcall(function()
      return c.create({
        name = "test-final-rep",
        c.root(c.node({
          c.arg("first_fixed", v.string()),
          c.repeated(c.arg("rest_files", v.string())),
          c.run(function(ctx) return ctx.args end),
        })),
      })
    end)

    assert.truthy(ok, "Expected compile to succeed for final repeated positional")
    local parsed = app:parse({ "main.lua", "util.lua", "config.lua" })
    assert.equal(parsed.args.first_fixed, "main.lua")
    assert.same(parsed.args.rest_files, { "util.lua", "config.lua" })
  end)

  it("rejects positional arguments declared inside c.inherit() (Section 16, Invariant 13)", function()
    assert.has_error(function()
      c.create({
        name = "test-inherit-arg",
        c.root(c.node({
          c.inherit(
            c.arg("illegal_inherited_arg", v.string())
          ),
          child = c.node({}),
        })),
      })
    end, "cannot be inherited")
  end)

  it("rejects impossible cardinality combinations where min > max", function()
    assert.has_error(function()
      local bad_arg = c.arg("bad", v.string())
      bad_arg.occurrence = { min = 5, max = 2 }

      c.create({
        name = "test-bad-cardinality",
        c.root(c.node({
          bad_arg,
        })),
      })
    end, "min (5) > max (2)")
  end)

  it("rejects multiple conflicting parser modes declared on the same node", function()
    assert.has_error(function()
      c.create({
        name = "test-conflicting-modes",
        c.root(c.node({
          c.leading(),
          c.ordered(), -- Conflicting!
        })),
      })
    end, "Conflicting parser modes")
  end)

  it("rejects multiple passthrough declarations on the same node", function()
    assert.has_error(function()
      c.create({
        name = "test-dup-passthrough",
        c.root(c.node({
          c.passthrough("first"),
          c.passthrough("second"),
        })),
      })
    end, "Multiple passthrough declarations")
  end)

end)
