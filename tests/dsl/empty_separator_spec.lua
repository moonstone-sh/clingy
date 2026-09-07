local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Empty adjacent option separators", function()
  local function compiler_app(with_completion)
    local define = c.option("-D", v.string())
    if with_completion then
      define = c.complete(c.values({ "optimize", "target=release" }), define)
    end

    return c.create({
      name = "compiler",
      c.root(c.node({
        c.short_clusters(),
        c.label("defines", c.repeated(c.separator({ "", " " }, define))),
        c.flag("-o", "--object"),
        c.flag("-p", "--preprocess"),
      })),
    })
  end

  it("aggregates adjacent and detached compiler defines", function()
    local parsed = compiler_app():parse({
      "-Doptimize",
      "-Dtarget=release",
      "-D", "debug=true",
    })
    assert.same(parsed.args.defines, { "optimize", "target=release", "debug=true" })
  end)

  it("keeps a bare adjacent option on detached-value handling", function()
    local app = compiler_app()
    assert.equal(app:parse({ "-D", "optimize" }).args.defines[1], "optimize")
    assert.has_error(function() app:parse({ "-D" }) end, "requires a value")
  end)

  it("selects the longest declared alias and separator deterministically", function()
    local app = c.create({
      name = "aliases",
      c.root(c.node({
        c.separator({ "", "=", " " }, c.option("short", "-D", v.string())),
        c.separator({ "", "=", " " }, c.option("long", "-Define", v.string())),
      })),
    })

    local parsed = app:parse({ "-Define=release" })
    assert.equal(parsed.args.long, "release")
    assert.is_nil(parsed.args.short)
    assert.equal(app:parse({ "-Define", "debug" }).args.long, "debug")
  end)

  it("rejects empty separators for flags and composed patterns", function()
    assert.has_error(function()
      c.separator("", c.flag("-D"))
    end, "cannot wrap a flag")
    assert.has_error(function()
      c.separator("")
    end, "does not accept blank or empty separators")
  end)

  it("recognizes an adjacent short option before considering flag clusters", function()
    local parsed = compiler_app():parse({ "-Doptimize" })
    assert.same(parsed.args.defines, { "optimize" })
    assert.equal(parsed.args.object, false)
    assert.equal(parsed.args.preprocess, false)
  end)

  it("completes an adjacent value and preserves its zero-width spelling", function()
    local resp = compiler_app(true):complete({ "compiler", "-Dtar" })
    assert.equal(#resp.candidates, 1)
    assert.equal(resp.candidates[1].value, "-Dtarget=release")
  end)
end)
