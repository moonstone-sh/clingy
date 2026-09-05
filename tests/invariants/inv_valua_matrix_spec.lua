local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant: Clingy <-> Valua Lexical Adaptation Matrix (Section 5 & 6)", function()

  it("adapts v.string directly without coercion", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--name", v.string()),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--name", "hello-world" })
    assert.equal(type(res.args.name), "string")
    assert.equal(res.args.name, "hello-world")
  end)

  it("adapts v.integer from string token to integer", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--count", v.integer()),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--count", "42" })
    assert.equal(type(res.args.count), "number")
    assert.equal(res.args.count, 42)
  end)

  it("adapts v.number from float string to number", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--rate", v.number()),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--rate", "3.1415" })
    assert.equal(type(res.args.rate), "number")
    assert.equal(res.args.rate, 3.1415)
  end)

  it("adapts v.boolean from 'true'/'false' and 'yes'/'no'", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--flag1", v.boolean()),
        c.option("--flag2", v.boolean()),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--flag1", "yes", "--flag2", "off" })
    assert.equal(res.args.flag1, true)
    assert.equal(res.args.flag2, false)
  end)

  it("validates string picklist", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--env", v.picklist({ "dev", "prod", "staging" })),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--env", "prod" })
    assert.equal(res.args.env, "prod")

    assert.has_error(function()
      app:parse({ "--env", "invalid_env" })
    end)
  end)

  it("adapts numeric picklist properly", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--level", v.picklist({ 1, 2, 3 })),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--level", "2" })
    assert.equal(res.args.level, 2)
  end)

  it("preserves base input domain in v.pipe without pre-coercing output type", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--doubled", v.pipe(
          v.string(),
          v.transform(function(val)
            return tonumber(val) * 2
          end)
        )),
        c.run(function(ctx) return ctx.args end),
      })),
    })
    local res = app:parse({ "--doubled", "21" })
    assert.equal(res.args.doubled, 42)
  end)

  it("validates v.check and v.custom constraints", function()
    local app = c.create({
      name = "test",
      c.root(c.node({
        c.option("--even", v.pipe(
          v.integer(),
          v.check(function(n) return n % 2 == 0 end, "Must be even")
        )),
      })),
    })
    local res = app:parse({ "--even", "4" })
    assert.equal(res.args.even, 4)

    assert.has_error(function()
      app:parse({ "--even", "5" })
    end, "Must be even")
  end)

  it("Section 6: Valua metadata default remains strictly descriptive and does NOT auto-populate ctx.args", function()
    local Port = v.annotate(
      v.integer(),
      {
        default = 8080,
        description = "Server listening port",
      }
    )

    local app = c.create({
      name = "test-desc-default",
      c.root(c.node({
        c.option("--port", Port),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    -- When --port is omitted, ctx.args.port must remain nil!
    local res = app:parse({})
    assert.equal(res.args.port, nil)
  end)

end)
