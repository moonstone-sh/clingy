local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("First-class c.define records", function()
  local function define_app()
    return c.create({
      name = "compiler",
      c.root(c.node({
        c.short_clusters(),
        c.label("defines", c.repeated(c.define("-D", {
          c.label("name", c.capture(v.string())),
          c.separator({ "=", " ", "-" }),
          c.label("value", c.capture(v.string())),
        }))),
        c.flag("-o", "--object"),
      })),
    })
  end

  it("parses all declared spellings and preserves record order and duplicates", function()
    local parsed = define_app():parse({
      "-Doptimize=releasefast",
      "-Doptimize", "releasefast",
      "-Doptimize-releasefast",
      "-Doptimize=releasefast",
    })
    assert.same(parsed.args.defines, {
      { name = "optimize", value = "releasefast" },
      { name = "optimize", value = "releasefast" },
      { name = "optimize", value = "releasefast" },
      { name = "optimize", value = "releasefast" },
    })
  end)

  it("claims its prefix before short-cluster expansion", function()
    local parsed = define_app():parse({ "-Dmode-fast", "-o" })
    assert.same(parsed.args.defines, { { name = "mode", value = "fast" } })
    assert.equal(parsed.args.object, true)
  end)

  it("requires the adjacent name and a nonempty value", function()
    local app = define_app()
    assert.has_error(function() app:parse({ "-D" }) end, "requires an adjacent name")
    assert.has_error(function() app:parse({ "-Dmode=" }) end, "requires a value")
    assert.has_error(function() app:parse({ "-Dmode" }) end, "requires a value")
    assert.has_error(function() app:parse({ "-Dmode", "--" }) end, "requires a value")
  end)

  it("validates each capture with its own schema", function()
    local app = c.create({
      c.root(c.node({
        c.label("defines", c.repeated(c.define("-D", {
          c.label("name", c.capture(v.string())),
          c.separator({ "=" }),
          c.label("value", c.capture(v.integer())),
        }))),
      })),
    })
    assert.equal(app:parse({ "-Dthreads=4" }).args.defines[1].value, 4)
    assert.has_error(function() app:parse({ "-Dthreads=fast" }) end, "field 'value'")
  end)

  it("rejects malformed record grammars and unsupported wrappers", function()
    assert.has_error(function()
      c.define("define", {})
    end, "starting with '-'")
    assert.has_error(function()
      c.define("-D", {
        c.label("value", c.capture(v.string())), c.separator("="), c.label("name", c.capture(v.string())),
      })
    end, "labelled 'name'")
    assert.has_error(function()
      c.define("-D", {
        c.label("name", c.capture(v.string())), c.separator({ "" }), c.label("value", c.capture(v.string())),
      })
    end, "does not accept blank or empty separators")

    local definition = c.define("-D", {
      c.label("name", c.capture(v.string())), c.separator({ "=" }), c.label("value", c.capture(v.string())),
    })
    assert.has_error(function() c.optional(definition) end, "cannot wrap c.define")
    assert.has_error(function() c.required(definition) end, "cannot wrap c.define")
    assert.has_error(function() c.inherit(definition) end, "cannot be inherited")
    assert.has_error(function() c.repeated(c.repeated(definition)) end, "exactly once")
    assert.has_error(function() c.complete(c.values({ "anything" }), definition) end, "cannot wrap c.define")
    assert.has_error(function()
      c.create({ c.root(c.node({ c.label("defines", definition) })) })
    end, "must be wrapped exactly once")
  end)

  it("only offers the record prefix and never guesses record fields", function()
    local app = define_app()
    local start = app:complete({ "compiler", "-" })
    local found = false
    for _, candidate in ipairs(start.candidates) do
      found = found or candidate.value == "-D"
    end
    assert.truthy(found)
    assert.equal(#app:complete({ "compiler", "-Dmode" }).candidates, 0)
    assert.equal(#app:complete({ "compiler", "-Dmode", "" }).candidates, 0)
  end)
end)
