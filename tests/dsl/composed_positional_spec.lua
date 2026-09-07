local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Composed positional token grammar", function()
  local environment = c.label("environment", c.capture(v.string()))
  local database = c.label("database", c.capture(v.boolean()))

  local function app_for(pattern)
    return c.create({
      name = "compose-test",
      c.root(c.node({
        run = c.node({
          pattern or c.compose(
            environment,
            c.separator(":"),
            c.literal("database"),
            c.separator("="),
            database
          ),
        }),
      })),
    })
  end

  it("consumes one argv token into independently typed labelled values", function()
    local app = app_for()
    local parsed = app:parse({ "run", "dev:database=true" })
    assert.equal(parsed.args.environment, "dev")
    assert.equal(parsed.args.database, true)
    assert.equal(parsed.route[2].args.environment, "dev")
    assert.equal(parsed.route[2].args.database, true)

    local received = nil
    local ctx_app = c.create({
      name = "compose-context",
      c.root(c.node({
        c.compose(environment, c.separator(":"), c.literal("database"), c.separator("="), database),
        c.run(function(ctx)
          received = { environment = ctx:get(environment), database = ctx:get(database) }
        end),
      })),
    })
    assert.equal(ctx_app:run({ "dev:database=true" }, { capture = true }), 0)
    assert.same(received, { environment = "dev", database = true })
  end)

  it("trims whitespace adjacent to separators by default, including newlines", function()
    local parsed = app_for():parse({ "run", "dev \n: \tdatabase \n= true" })
    assert.equal(parsed.args.environment, "dev")
    assert.equal(parsed.args.database, true)
  end)

  it("preserves adjacent whitespace when a separator opts out of trimming", function()
    local env = c.label("environment", c.capture(v.string()))
    local enabled = c.label("enabled", c.capture(v.boolean()))
    local app = app_for(c.compose(
      env,
      c.separator(":", { trim = false }),
      c.literal("database"),
      c.separator("=", { trim = false }),
      enabled
    ))
    local parsed = app:parse({ "run", "dev :database=true" })
    assert.equal(parsed.args.environment, "dev ")
    assert.equal(parsed.args.enabled, true)
  end)

  it("requires the declared literal shape and validates each capture", function()
    local app = app_for()
    assert.has_error(function()
      app:parse({ "run", "dev:cache=true" })
    end, "does not match fixed pattern")
    assert.has_error(function()
      app:parse({ "run", "dev:database=perhaps" })
    end, "composed capture 'database'")
  end)

  it("uses full-token lexical matching rather than a global delimiter heuristic", function()
    local value = c.label("value", c.capture(v.string()))
    local app = app_for(c.compose(c.literal("@"), value, c.literal(".cfg")))
    assert.equal(app:parse({ "run", "@dev.cfg" }).args.value, "dev")
    assert.has_error(function()
      app:parse({ "run", "@dev.cfg.bak" })
    end, "does not match fixed pattern")
  end)

  it("rejects malformed, ambiguous, colliding, and inherited patterns at compile time", function()
    assert.has_error(function()
      c.create({ c.root(c.node({ c.compose(c.literal("only-fixed")) })) })
    end, "requires at least one labelled capture")
    assert.has_error(function()
      c.create({ c.root(c.node({ c.compose(
        c.label("left", c.capture(v.string())),
        c.label("right", c.capture(v.string()))
      ) })) })
    end, "adjacent captures")
    assert.has_error(function()
      c.create({ c.root(c.node({ c.compose(
        c.label("same", c.capture(v.string())), c.literal(":"),
        c.label("same", c.capture(v.string()))
      ) })) })
    end, "duplicate capture label")
    assert.has_error(function()
      c.create({ c.root(c.node({
        c.arg("environment", v.string()),
        c.compose(c.label("environment", c.capture(v.string()))),
      })) })
    end, "Output-key collision")
    assert.has_error(function()
      c.create({ c.root(c.node({
        c.inherit(c.compose(c.label("environment", c.capture(v.string())))),
        run = c.node({}),
      })) })
    end, "c.compose on node 'root' cannot be inherited")
    assert.has_error(function()
      c.label(" ", c.capture(v.string()))
    end, "c.label label")
  end)

  it("suppresses completions for an atomic composed token", function()
    local response = app_for():complete({ "compose-test", "dev:dat" })
    assert.equal(#response.candidates, 0)

    -- Partial parsing also consumes a completed composite without inventing a
    -- nil result key or exposing capture-specific completion candidates.
    local after = app_for():complete({ "compose-test", "run", "dev:database=true", "" })
    assert.equal(#after.candidates, 0)
  end)
end)
