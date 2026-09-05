local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Hostile Edge Cases", function()
  it("Complex nested subcommand routes with interspersed vs leading vs ordered modes", function()
    local app = c.create({
      name = "hostile-nesting",
      c.root(c.node({
        c.inherit(c.interspersed()),
        cmd1 = c.node({
          c.leading(),
          c.flag("-a"),
          cmd2 = c.node({
            c.ordered(),
            c.flag("-b"),
            c.arg("pos1", v.string()),
            c.flag("-c"),
            c.run(function(ctx) return ctx.args end)
          })
        })
      }))
    })

    local p = app:parse({"cmd1", "-a", "cmd2", "-b", "val", "-c"})
    assert.equal(p.args.a, true)
    assert.equal(p.args.b, true)
    assert.equal(p.args.c, true)
    assert.equal(p.args.pos1, "val")

    assert.has_error(function()
      app:parse({"cmd1", "cmd2", "-a", "-b", "val", "-c"}) -- -a is not allowed here since cmd1 is leading and cmd2 is a positional for cmd1? wait, child command routing precedence.
    end)
  end)

  it("Short flag clustering with multiple short flags mixed with local and inherited flags", function()
    local app = c.create({
      name = "hostile-clusters",
      c.root(c.node({
        c.inherit(c.short_clusters(), c.flag("-x")),
        cmd = c.node({
          c.flag("-y"),
          c.flag("-z"),
          c.run(function(ctx) return ctx.args end)
        })
      }))
    })
    
    local p = app:parse({"cmd", "-xyzx"})
    assert.equal(p.args.x, true)
    assert.equal(p.args.y, true)
    assert.equal(p.args.z, true)
  end)

  it("Cardinality edge cases: repeated optional positionals", function()
    local app = c.create({
      name = "hostile-cardinality",
      c.root(c.node({
        c.optional(c.repeated(c.arg("opt_args", v.string()))),
        c.run(function(ctx) return ctx.args end)
      }))
    })

    local p1 = app:parse({})
    assert.same(p1.args.opt_args, {})

    local p2 = app:parse({"a", "b", "c"})
    assert.same(p2.args.opt_args, {"a", "b", "c"})
  end)
end)
