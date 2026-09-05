local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 8: Short Flag Clustering (c.short_clusters)", function()

  describe("Clustering enabled with c.short_clusters()", function()
    local app = c.create({
      name = "test-clustering-enabled",
      c.root(c.node({
        c.short_clusters(),

        c.flag("-x", "--extract"),
        c.flag("-f", "--force"),
        c.flag("-v", "--verbose"),
        c.flag("-z", "--gzip"),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    it("expands -xfv into -x, -f, and -v flags", function()
      local parsed = app:parse({ "-xfv" })
      assert.equal(parsed.args.extract, true)
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.verbose, true)
      assert.equal(parsed.args.gzip, false)
    end)

    it("expands 4-flag cluster -xfvz", function()
      local parsed = app:parse({ "-xfvz" })
      assert.equal(parsed.args.extract, true)
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.verbose, true)
      assert.equal(parsed.args.gzip, true)
    end)

    it("repeated flags inside cluster remain idempotent: -vvv", function()
      local parsed = app:parse({ "-vvv" })
      assert.equal(parsed.args.verbose, true)
    end)
  end)

  describe("Clustering disabled (default)", function()
    local app = c.create({
      name = "test-clustering-disabled",
      c.root(c.node({
        -- short_clusters NOT specified
        c.flag("-x", "--extract"),
        c.flag("-f", "--force"),
        c.flag("-v", "--verbose"),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    it("accepts separate single short flags: -x -f -v", function()
      local parsed = app:parse({ "-x", "-f", "-v" })
      assert.equal(parsed.args.extract, true)
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.verbose, true)
    end)

    it("rejects cluster -xfv when short_clusters is disabled", function()
      assert.has_error(function()
        app:parse({ "-xfv" })
      end, "Unknown option")
    end)
  end)

  describe("Clusters mixing local and inherited flags (Section 13, Section 46)", function()
    local app = c.create({
      name = "test-cluster-mixed",
      c.root(c.node({
        c.inherit(
          c.short_clusters(),
          c.flag("-v", "--verbose")
        ),

        build = c.node({
          c.flag("-f", "--force"),
          c.flag("-x", "--extract"),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    it("accepts cluster combining inherited -v and local -f and -x: -vfx", function()
      local parsed = app:parse({ "build", "-vfx" })
      assert.equal(parsed.args.verbose, true)
      assert.equal(parsed.args.force, true)
      assert.equal(parsed.args.extract, true)
    end)

    it("rejects cluster if it contains an unknown short flag character", function()
      assert.has_error(function()
        app:parse({ "build", "-vfq" })
      end, "Unknown option")
    end)
  end)

  describe("Section 13: Only zero-value short flags cluster in v0", function()
    local app = c.create({
      name = "test-cluster-options",
      c.root(c.node({
        c.short_clusters(),

        c.flag("-x", "--extract"),
        c.option("-j", "--jobs", v.integer()),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    it("rejects non-flag option inside cluster like -xj", function()
      assert.has_error(function()
        app:parse({ "-xj" })
      end, "Unknown option")
    end)
  end)

end)
