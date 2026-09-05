local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 3 & 7: Grammar Modes (Interspersed, Leading, Ordered)", function()

  describe("Mode 1: interspersed (default)", function()
    local app = c.create({
      name = "test-interspersed",
      c.root(c.node({
        copy = c.node({
          c.interspersed(),

          c.arg("source", v.string()),
          c.arg("destination", v.string()),
          c.flag("-f", "--force"),
          c.option("-m", "--mode", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    it("accepts flags before positionals: copy -f src dst", function()
      local parsed = app:parse({ "copy", "-f", "src", "dst" })
      assert.equal(parsed.args.source, "src")
      assert.equal(parsed.args.destination, "dst")
      assert.equal(parsed.args.force, true)
    end)

    it("accepts flags between positionals: copy src -f dst", function()
      local parsed = app:parse({ "copy", "src", "-f", "dst" })
      assert.equal(parsed.args.source, "src")
      assert.equal(parsed.args.destination, "dst")
      assert.equal(parsed.args.force, true)
    end)

    it("accepts flags and options after positionals: copy src dst -f --mode fast", function()
      local parsed = app:parse({ "copy", "src", "dst", "-f", "--mode", "fast" })
      assert.equal(parsed.args.source, "src")
      assert.equal(parsed.args.destination, "dst")
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.mode, "fast")
    end)

    it("preserves relative positional order regardless of flag interspersion", function()
      local p1 = app:parse({ "copy", "-f", "first", "second" })
      local p2 = app:parse({ "copy", "first", "-f", "second" })
      local p3 = app:parse({ "copy", "first", "second", "-f" })

      assert.equal(p1.args.source, "first")
      assert.equal(p1.args.destination, "second")
      assert.equal(p2.args.source, "first")
      assert.equal(p2.args.destination, "second")
      assert.equal(p3.args.source, "first")
      assert.equal(p3.args.destination, "second")
    end)
  end)

  describe("Mode 2: leading", function()
    local app = c.create({
      name = "test-leading",
      c.root(c.node({
        copy = c.node({
          c.leading(),

          c.arg("source", v.string()),
          c.arg("destination", v.string()),
          c.flag("-f", "--force"),
          c.option("-m", "--mode", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    it("accepts options before positionals: copy -f --mode safe src dst", function()
      local parsed = app:parse({ "copy", "-f", "--mode", "safe", "src", "dst" })
      assert.equal(parsed.args.source, "src")
      assert.equal(parsed.args.destination, "dst")
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.mode, "safe")
    end)

    it("rejects option appearing after positional consumption starts: copy src -f dst", function()
      assert.has_error(function()
        app:parse({ "copy", "src", "-f", "dst" })
      end)
    end)

    it("rejects option appearing after all positionals: copy src dst -f", function()
      assert.has_error(function()
        app:parse({ "copy", "src", "dst", "-f" })
      end)
    end)
  end)

  describe("Mode 3: ordered", function()
    local app = c.create({
      name = "test-ordered",
      c.root(c.node({
        legacy = c.node({
          c.ordered(),

          c.flag("--prepare"),
          c.arg("source", v.string()),
          c.flag("--commit"),
          c.arg("destination", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    it("accepts tokens strictly matching declared order: legacy --prepare in.txt --commit out.txt", function()
      local parsed = app:parse({ "legacy", "--prepare", "in.txt", "--commit", "out.txt" })
      assert.equal(parsed.args.prepare, true)
      assert.equal(parsed.args.source, "in.txt")
      assert.equal(parsed.args.commit, true)
      assert.equal(parsed.args.destination, "out.txt")
    end)

    it("allows skipping optional declarations: legacy in.txt --commit out.txt", function()
      local parsed = app:parse({ "legacy", "in.txt", "--commit", "out.txt" })
      assert.equal(parsed.args.prepare, false)
      assert.equal(parsed.args.source, "in.txt")
      assert.equal(parsed.args.commit, true)
      assert.equal(parsed.args.destination, "out.txt")
    end)

    it("rejects tokens appearing out of declared order: legacy --commit in.txt out.txt", function()
      assert.has_error(function()
        app:parse({ "legacy", "--commit", "in.txt", "out.txt" })
      end, "Ordered grammar error")
    end)

    it("rejects flag placed after its slot: legacy in.txt out.txt --commit", function()
      assert.has_error(function()
        app:parse({ "legacy", "in.txt", "out.txt", "--commit" })
      end)
    end)
  end)

  describe("Section 12: Parser policy inheritance and overrides", function()
    local app = c.create({
      name = "test-policy-inherit",
      c.root(c.node({
        c.inherit(
          c.interspersed()
        ),

        default_sub = c.node({
          c.arg("val", v.string()),
          c.flag("-v", "--verbose"),
          c.run(function(ctx) return ctx.args end),
        }),

        leading_sub = c.node({
          -- Override interspersed with leading
          c.leading(),

          c.arg("val", v.string()),
          c.flag("-v", "--verbose"),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    it("default_sub inherits interspersed mode from root", function()
      local parsed = app:parse({ "default_sub", "hello", "-v" })
      assert.equal(parsed.args.val, "hello")
      assert.equal(parsed.args.verbose, true)
    end)

    it("leading_sub overrides mode to leading and rejects flag after positional", function()
      local ok_parse = app:parse({ "leading_sub", "-v", "hello" })
      assert.equal(ok_parse.args.val, "hello")
      assert.equal(ok_parse.args.verbose, true)

      assert.has_error(function()
        app:parse({ "leading_sub", "hello", "-v" })
      end)
    end)
  end)

end)
