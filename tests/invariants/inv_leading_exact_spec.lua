local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant: Leading Mode Exact Semantics (Section 1)", function()

  local function create_copy_app()
    return c.create({
      name = "copy",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose")
        ),

        sub = c.node({
          c.leading(),
          c.flag("-f", "--force"),
          c.option("-m", "--mode", v.string()),
          c.arg("source", v.string()),
          c.arg("destination", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),

        calc = c.node({
          c.leading(),
          c.flag("-r", "--round"),
          c.arg("value", v.integer()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })
  end

  it("allows leading flag and option before positional arguments", function()
    local app = create_copy_app()
    local res = app:parse({ "sub", "-f", "-m", "fast", "src.txt", "dst.txt" })
    assert.truthy(res)
    assert.equal(res.args.force, true)
    assert.equal(res.args.mode, "fast")
    assert.equal(res.args.source, "src.txt")
    assert.equal(res.args.destination, "dst.txt")
  end)

  it("rejects leading flag after positional argument with structured misplaced option error", function()
    local app = create_copy_app()
    local ok, err = pcall(function()
      app:parse({ "sub", "src.txt", "-f", "dst.txt" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Misplaced option error.*'-f'.*leading%-mode")
  end)

  it("rejects known long option after positional argument with misplaced option error", function()
    local app = create_copy_app()
    local ok, err = pcall(function()
      app:parse({ "sub", "src.txt", "--force", "dst.txt" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Misplaced option error.*'--force'.*leading%-mode")
  end)

  it("rejects inherited named option after positional argument with misplaced option error", function()
    local app = create_copy_app()
    local ok, err = pcall(function()
      app:parse({ "sub", "src.txt", "-v", "dst.txt" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Misplaced option error.*'-v'.*leading%-mode")
  end)

  it("consumes negative-number positional argument when not matching a named alias", function()
    local app = create_copy_app()
    local res = app:parse({ "calc", "-1" })
    assert.truthy(res)
    assert.equal(res.args.value, -1)
    assert.equal(res.args.round, false)
  end)

  it("consumes hyphen-prefixed positional argument when not matching a named alias", function()
    local app = create_copy_app()
    -- After positional consumption begins on sub (source = "src.txt"), destination consumes "-custom-dest"
    local res = app:parse({ "sub", "src.txt", "-custom-dest" })
    assert.truthy(res)
    assert.equal(res.args.source, "src.txt")
    assert.equal(res.args.destination, "-custom-dest")
  end)

  it("rejects unknown --foo after positional consumption as unexpected argument", function()
    local app = create_copy_app()
    local ok, err = pcall(function()
      app:parse({ "sub", "src.txt", "dst.txt", "--foo" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Unexpected positional argument '%-%-foo'")
  end)

  it("allows '--' before hyphen-prefixed positional without ambiguity", function()
    local app = create_copy_app()
    local res = app:parse({ "calc", "-r", "--", "-42" })
    assert.truthy(res)
    assert.equal(res.args.round, true)
    assert.equal(res.args.value, -42)
  end)

end)
