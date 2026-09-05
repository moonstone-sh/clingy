local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 9, 10, 11: Segment Boundaries, Local Isolation, and Inherited Persistence", function()

  local app = c.create({
    name = "meteorite",
    version = "0.1.0",

    c.root(c.node({
      -- Inherited root flag (Invariant 11)
      c.inherit(
        c.flag("-v", "--verbose")
      ),
      -- Local root flag (Invariant 10)
      c.flag("--root-local"),

      init = c.node({
        -- Inherited subtree flag
        c.inherit(
          c.flag("--json")
        ),
        -- Local init flag
        c.flag("--init-local"),

        c.arg("profile", v.string()),

        instant = c.node({
          c.flag("-n", "--now"),
          c.run(function(ctx) return ctx.args end),
        }),
      }),

      build = c.node({
        c.repeated(c.option("-D", "--define", v.string())),
        c.run(function(ctx) return ctx.args end),
      }),
    })),
  })

  it("Invariant 9: routing transitions define segment boundaries (root -> init -> instant)", function()
    local parsed = app:parse({ "--root-local", "init", "--init-local", "staging", "instant", "-n" })
    assert.truthy(parsed)
    assert.equal(#parsed.route, 3)
    assert.equal(parsed.route[1].node, "root")
    assert.equal(parsed.route[2].node, "init")
    assert.equal(parsed.route[3].node, "instant")
    assert.equal(parsed.args.root_local, true)
    assert.equal(parsed.args.init_local, true)
    assert.equal(parsed.args.profile, "staging")
    assert.equal(parsed.args.now, true)
  end)

  it("Invariant 10: local root flag stops being visible after segment transition into init", function()
    -- Valid before transition
    local p_ok = app:parse({ "--root-local", "init", "production", "instant" })
    assert.equal(p_ok.args.root_local, true)

    -- Invalid after transition into init
    assert.has_error(function()
      app:parse({ "init", "--root-local", "production", "instant" })
    end, "Unknown option")

    -- Invalid after transition into instant
    assert.has_error(function()
      app:parse({ "init", "production", "instant", "--root-local" })
    end, "Unknown option")
  end)

  it("Invariant 10: local init flag stops being visible after segment transition into instant", function()
    -- Valid during init segment
    local p_ok = app:parse({ "init", "--init-local", "development", "instant" })
    assert.equal(p_ok.args.init_local, true)

    -- Invalid after transition into instant
    assert.has_error(function()
      app:parse({ "init", "development", "instant", "--init-local" })
    end, "Unknown option")
  end)

  it("Invariant 11: inherited ancestor flag remains visible downward across all segments", function()
    -- Available at root segment
    local p1 = app:parse({ "--verbose", "init", "test", "instant" })
    assert.equal(p1.args.verbose, true)

    -- Available at init segment
    local p2 = app:parse({ "init", "--verbose", "test", "instant" })
    assert.equal(p2.args.verbose, true)

    -- Available between positionals and instant
    local p3 = app:parse({ "init", "test", "--verbose", "instant" })
    assert.equal(p3.args.verbose, true)

    -- Available at leaf instant segment
    local p4 = app:parse({ "init", "test", "instant", "--verbose" })
    assert.equal(p4.args.verbose, true)
  end)

  it("Section 5: inherited subtree flag (--json) is visible in descendants, but not before or across siblings", function()
    -- Visible in init segment
    local p1 = app:parse({ "init", "--json", "test", "instant" })
    assert.equal(p1.args.json, true)

    -- Visible in instant segment
    local p2 = app:parse({ "init", "test", "instant", "--json" })
    assert.equal(p2.args.json, true)

    -- NOT visible before init (at root)
    assert.has_error(function()
      app:parse({ "--json", "init", "test", "instant" })
    end, "Unknown option")

    -- NOT visible in sibling branch (build)
    assert.has_error(function()
      app:parse({ "build", "--json" })
    end, "Unknown option")
  end)

  describe("Section 22: Child transition vs positional consumption precedence", function()
    local trans_app = c.create({
      name = "test-precedence",
      c.root(c.node({
        parent = c.node({
          c.arg("req_arg", v.string()),
          c.optional(c.repeated(c.arg("opt_args", v.string()))),

          child = c.node({
            c.flag("--child-flag"),
            c.run(function(ctx) return ctx.args end),
          }),
        }),
      })),
    })

    it("child transition takes precedence over repeated positionals once required minimums are satisfied", function()
      local parsed = trans_app:parse({ "parent", "first_value", "child", "--child-flag" })
      assert.equal(#parsed.route, 3)
      assert.equal(parsed.route[2].node, "parent")
      assert.equal(parsed.route[3].node, "child")
      assert.equal(parsed.args.req_arg, "first_value")
      assert.equal(parsed.args.child_flag, true)
    end)

    it("token matching child name is consumed as positional if required positional minimum is NOT yet satisfied", function()
      local req_first_app = c.create({
        name = "test-req-first",
        c.root(c.node({
          cmd = c.node({
            c.arg("profile", v.string()),

            instant = c.node({
              c.run(function(ctx) return ctx.args end),
            }),
          }),
        })),
      })

      -- Token "instant" satisfies required arg "profile" when only one token provided
      local parsed = req_first_app:parse({ "cmd", "instant" })
      assert.equal(#parsed.route, 2)
      assert.equal(parsed.route[2].node, "cmd")
      assert.equal(parsed.args.profile, "instant")
    end)
  end)

end)
