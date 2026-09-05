local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 1 & 2: Single Ownership and Explicit Inheritance", function()

  it("Invariant 1: argument declaration has exactly one owner node", function()
    local app = c.create({
      name = "test-ownership",
      c.root(c.node({
        c.flag("-v", "--verbose"),

        init = c.node({
          c.flag("--json"),
          c.arg("profile", v.string()),

          instant = c.node({
            c.flag("-n", "--now"),
            c.run(function(ctx) return ctx.args end),
          }),
        }),
      })),
    })

    local graph = app:graph()
    local root_ir = graph.root
    local init_ir = root_ir.children["init"]
    local instant_ir = init_ir.children["instant"]

    assert.equal(#root_ir.flags, 1)
    assert.equal(root_ir.flags[1].owner, "root")
    assert.equal(root_ir.flags[1].result_key, "verbose")

    assert.equal(#init_ir.flags, 1)
    assert.equal(init_ir.flags[1].owner, "init")
    assert.equal(init_ir.flags[1].result_key, "json")

    assert.equal(#init_ir.args, 1)
    assert.equal(init_ir.args[1].owner, "init")
    assert.equal(init_ir.args[1].name, "profile")

    assert.equal(#instant_ir.flags, 1)
    assert.equal(instant_ir.flags[1].owner, "instant")
    assert.equal(instant_ir.flags[1].result_key, "now")
  end)

  it("Invariant 2 & 10: uninherited parent flag is NOT visible to child after transition", function()
    local executed = false
    local app = c.create({
      name = "test-no-inherit",
      c.root(c.node({
        -- verbose is local to root (NOT in c.inherit)
        c.flag("-v", "--verbose"),

        sub = c.node({
          c.flag("-f", "--force"),
          c.run(function(ctx)
            executed = true
            return ctx.args
          end),
        }),
      })),
    })

    -- Calling 'sub' and passing root's local flag '--verbose' after 'sub' must fail
    assert.has_error(function()
      app:parse({ "sub", "--verbose" })
    end, "Unknown option")

    assert.has_error(function()
      app:parse({ "sub", "-v" })
    end, "Unknown option")
  end)

  it("Invariant 2 & 11: child sees parent flags declared inside c.inherit()", function()
    local result_args = nil
    local app = c.create({
      name = "test-inherit",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose"),
          c.option("-c", "--config", v.string())
        ),

        sub = c.node({
          c.flag("-f", "--force"),
          c.run(function(ctx)
            result_args = ctx.args
          end),
        }),
      })),
    })

    local parsed = app:parse({ "sub", "--verbose", "-c", "app.json", "--force" })
    assert.truthy(parsed)
    assert.equal(parsed.args.verbose, true)
    assert.equal(parsed.args.config, "app.json")
    assert.equal(parsed.args.force, true)
  end)

  it("Invariant 2: inherited flags cascade downward through multiple generations", function()
    local app = c.create({
      name = "test-multi-gen",
      c.root(c.node({
        c.inherit(
          c.flag("-g", "--global-flag")
        ),

        level1 = c.node({
          c.inherit(
            c.flag("-l", "--level1-flag")
          ),

          level2 = c.node({
            c.flag("-d", "--deep-flag"),
            c.run(function(ctx) return ctx.args end),
          }),
        }),
      })),
    })

    local parsed = app:parse({ "level1", "level2", "--global-flag", "--level1-flag", "--deep-flag" })
    assert.equal(parsed.args.global_flag, true)
    assert.equal(parsed.args.level1_flag, true)
    assert.equal(parsed.args.deep_flag, true)
  end)

  it("Section 5: inheritance is downward only (parent cannot see child's flags)", function()
    local app = c.create({
      name = "test-downward-only",
      c.root(c.node({
        c.run(function(ctx) return ctx.args end),

        child = c.node({
          c.inherit(
            c.flag("-c", "--child-flag")
          ),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    -- Root cannot see child's flag
    assert.has_error(function()
      app:parse({ "--child-flag" })
    end, "Unknown option")
  end)

  it("Section 5: siblings do not inherit each other's flags", function()
    local app = c.create({
      name = "test-siblings",
      c.root(c.node({
        cmd1 = c.node({
          c.inherit(
            c.flag("-a", "--alpha")
          ),
        }),

        cmd2 = c.node({
          c.flag("-b", "--beta"),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    -- cmd2 cannot see cmd1's inherited flag
    assert.has_error(function()
      app:parse({ "cmd2", "--alpha" })
    end, "Unknown option")
  end)

  it("Section 6 & Invariant 2: root inheritance is global composition across all commands", function()
    local app = c.create({
      name = "test-root-global",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose"),
          c.flag("-q", "--quiet"),
          c.flag("--json")
        ),

        cmd_a = c.node({ c.run(function(ctx) return ctx.args end) }),
        cmd_b = c.node({ c.run(function(ctx) return ctx.args end) }),
      })),
    })

    local parsed_a = app:parse({ "cmd_a", "--verbose", "--json" })
    assert.equal(parsed_a.args.verbose, true)
    assert.equal(parsed_a.args.json, true)
    assert.equal(parsed_a.args.quiet, false)

    local parsed_b = app:parse({ "cmd_b", "--quiet" })
    assert.equal(parsed_b.args.quiet, true)
    assert.equal(parsed_b.args.verbose, false)
  end)

  it("Section 7: c.group is composition only, not visibility, unless wrapped in c.inherit", function()
    local common_flags = c.group({
      c.flag("-x", "--extra"),
      c.flag("-y", "--yellow"),
    })

    local app = c.create({
      name = "test-group",
      c.root(c.node({
        -- Group included directly without c.inherit -> local to parent
        common_flags,

        child = c.node({
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    -- Root sees --extra
    local parsed_root = app:parse({ "--extra" })
    assert.equal(parsed_root.args.extra, true)

    -- Child does NOT see --extra because it was not in c.inherit
    assert.has_error(function()
      app:parse({ "child", "--extra" })
    end, "Unknown option")
  end)

end)
