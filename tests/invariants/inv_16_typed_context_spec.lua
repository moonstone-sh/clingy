local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 16: Typed Context Delivery and Route Ownership", function()

  it("delivers typed and validated values in ctx.args", function()
    local captured_ctx = nil

    local app = c.create({
      name = "test-typed-ctx",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose")
        ),

        deploy = c.node({
          c.option("-p", "--port", v.integer()),
          c.option("-r", "--ratio", v.number()),
          c.repeated(c.option("-t", "--tag", v.string())),
          c.arg("environment", v.picklist({ "staging", "prod" })),

          c.run(function(ctx)
            captured_ctx = ctx
            return { status = "ok" }
          end),
        }),
      })),
    })

    local code = app:run({ "--verbose", "deploy", "-p", "9000", "-r", "0.75", "-t", "v1", "-t", "v2", "prod" }, { capture = true })
    assert.equal(code, 0)
    assert.truthy(captured_ctx)

    -- Invariant 16: Typed delivery
    assert.equal(type(captured_ctx.args.verbose), "boolean")
    assert.equal(captured_ctx.args.verbose, true)

    assert.equal(type(captured_ctx.args.port), "number")
    assert.equal(captured_ctx.args.port, 9000)

    assert.equal(type(captured_ctx.args.ratio), "number")
    assert.truthy(math.abs(captured_ctx.args.ratio - 0.75) < 0.001)

    assert.equal(type(captured_ctx.args.tag), "table")
    assert.same(captured_ctx.args.tag, { "v1", "v2" })

    assert.equal(type(captured_ctx.args.environment), "string")
    assert.equal(captured_ctx.args.environment, "prod")
  end)

  it("Section 24: ctx.route records ownership table per segment along executed path", function()
    local captured_route = nil

    local app = c.create({
      name = "test-route-ownership",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose")
        ),

        init = c.node({
          c.inherit(
            c.flag("--json")
          ),
          c.arg("profile", v.string()),

          instant = c.node({
            c.flag("-n", "--now"),
            c.run(function(ctx)
              captured_route = ctx.route
            end),
          }),
        }),
      })),
    })

    app:run({ "init", "development", "instant", "-v", "--json", "-n" }, { capture = true })

    assert.truthy(captured_route)
    assert.equal(#captured_route, 3)

    -- Segment 1: root
    assert.equal(captured_route[1].node, "root")
    -- Invariant 1: verbose was owned by root
    assert.equal(captured_route[1].args.verbose, true)

    -- Segment 2: init
    assert.equal(captured_route[2].node, "init")
    -- Invariant 1: profile and json owned by init
    assert.equal(captured_route[2].args.profile, "development")
    assert.equal(captured_route[2].args.json, true)

    -- Segment 3: instant
    assert.equal(captured_route[3].node, "instant")
    -- Invariant 1: now owned by instant
    assert.equal(captured_route[3].args.now, true)
  end)

  it("supports dual-access keys (foo_bar and foo-bar) on ctx.args", function()
    local captured_args = nil

    local app = c.create({
      name = "test-dual-access",
      c.root(c.node({
        c.option("--target-env", v.string()),
        c.flag("--dry-run"),
        c.run(function(ctx)
          captured_args = ctx.args
        end),
      })),
    })

    app:run({ "--target-env", "staging", "--dry-run" })

    assert.truthy(captured_args)
    -- Underscore access
    assert.equal(captured_args.target_env, "staging")
    assert.equal(captured_args.dry_run, true)

    -- Dash access
    assert.equal(captured_args["target-env"], "staging")
    assert.equal(captured_args["dry-run"], true)
  end)

  it("provides ctx telemetry and event helpers", function()
    local events_emitted = {}

    local app = c.create({
      name = "test-helpers",
      c.root(c.node({
        c.run(function(ctx)
          ctx:progress("build", 50, "Compiling")
          ctx:milestone("Build complete")
          ctx:log("info", "All assets generated")
          ctx:result({ count = 42 })
        end),
      })),
    })

    local code = app:run({}, {
      capture = true,
      composer_mode = "plain",
    })
    assert.equal(code, 0)
  end)

end)
