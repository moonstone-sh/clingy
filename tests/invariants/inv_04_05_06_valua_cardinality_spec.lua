local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 4, 5, 6: Cardinality Algebra, Lexical Coercion, and Valua Validation", function()

  describe("Cardinality Algebra (Invariant 4, Section 17)", function()
    it("verifies base cardinalities of declarations", function()
      local a = c.arg("file", v.string())
      assert.equal(a.occurrence.min, 1)
      assert.equal(a.occurrence.max, 1)
      assert.equal(a.aggregate, "scalar")

      local opt = c.option("-p", "--port", v.integer())
      assert.equal(opt.occurrence.min, 0)
      assert.equal(opt.occurrence.max, 1)
      assert.equal(opt.aggregate, "scalar")

      local fl = c.flag("-v", "--verbose")
      assert.equal(fl.occurrence.min, 0)
      assert.equal(fl.occurrence.max, 1)
      assert.equal(fl.default, false)
    end)

    it("c.optional sets occurrence.min = 0", function()
      local a = c.optional(c.arg("file", v.string()))
      assert.equal(a.occurrence.min, 0)
      assert.equal(a.occurrence.max, 1)

      local app = c.create({
        name = "test-optional-arg",
        c.root(c.node({
          a,
          c.run(function(ctx) return ctx.args end),
        })),
      })

      local parsed_empty = app:parse({})
      assert.is_nil(parsed_empty.args.file)

      local parsed_val = app:parse({ "readme.md" })
      assert.equal(parsed_val.args.file, "readme.md")
    end)

    it("c.required sets occurrence.min = 1 for options", function()
      local opt = c.required(c.option("-k", "--key", v.string()))
      assert.equal(opt.occurrence.min, 1)

      local app = c.create({
        name = "test-required-option",
        c.root(c.node({
          opt,
          c.run(function(ctx) return ctx.args end),
        })),
      })

      assert.has_error(function()
        app:parse({})
      end, "Missing required option")

      local parsed = app:parse({ "--key", "secret123" })
      assert.equal(parsed.args.key, "secret123")
    end)

    it("c.repeated sets occurrence.max = nil and aggregate = 'array'", function()
      local opt = c.repeated(c.option("-D", "--define", v.string()))
      assert.equal(opt.occurrence.min, 0)
      assert.is_nil(opt.occurrence.max)
      assert.equal(opt.aggregate, "array")

      local app = c.create({
        name = "test-repeated-opt",
        c.root(c.node({
          opt,
          c.run(function(ctx) return ctx.args end),
        })),
      })

      local parsed = app:parse({ "-D", "A=1", "-D", "B=2", "--define", "C=3" })
      assert.same(parsed.args.define, { "A=1", "B=2", "C=3" })
    end)

    it("c.repeated with positional arguments aggregates into array", function()
      local app = c.create({
        name = "test-repeated-arg",
        c.root(c.node({
          c.repeated(c.arg("files", v.string())),
          c.run(function(ctx) return ctx.args end),
        })),
      })

      local parsed = app:parse({ "a.txt", "b.txt", "c.txt" })
      assert.same(parsed.args.files, { "a.txt", "b.txt", "c.txt" })
    end)

    it("composition: c.optional(c.repeated(c.arg(...))) allows zero or many positionals", function()
      local app = c.create({
        name = "test-opt-rep-arg",
        c.root(c.node({
          c.optional(c.repeated(c.arg("items", v.string()))),
          c.run(function(ctx) return ctx.args end),
        })),
      })

      local p_empty = app:parse({})
      assert.is_nil(p_empty.args.items)

      local p_vals = app:parse({ "x", "y" })
      assert.same(p_vals.args.items, { "x", "y" })
    end)
  end)

  describe("Lexical Coercion (Invariant 6, Section 20)", function()
    local app = c.create({
      name = "test-coercion",
      c.root(c.node({
        c.option("-i", "--int-val", v.integer()),
        c.option("-n", "--num-val", v.number()),
        c.option("-b", "--bool-val", v.boolean()),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    it("coerces integer strings to integers", function()
      local parsed = app:parse({ "-i", "1024" })
      assert.equal(type(parsed.args.int_val), "number")
      assert.equal(parsed.args.int_val, 1024)
    end)

    it("coerces floating point number strings to numbers", function()
      local parsed = app:parse({ "-n", "3.14159" })
      assert.equal(type(parsed.args.num_val), "number")
      assert.truthy(math.abs(parsed.args.num_val - 3.14159) < 0.0001)
    end)

    it("coerces boolean strings 'true' and 'false'", function()
      local p1 = app:parse({ "-b", "true" })
      assert.equal(p1.args.bool_val, true)

      local p2 = app:parse({ "-b", "false" })
      assert.equal(p2.args.bool_val, false)
    end)
  end)

  describe("Valua Semantic Validation (Invariant 5, Section 19)", function()
    local PortSchema = v.pipe(
      v.integer(),
      v.min_value(1),
      v.max_value(65535)
    )

    local EnvSchema = v.picklist({ "development", "staging", "production" })

    local app = c.create({
      name = "test-valua",
      c.root(c.node({
        c.option("-p", "--port", PortSchema),
        c.arg("env", EnvSchema),
        c.run(function(ctx) return ctx.args end),
      })),
    })

    it("accepts values that satisfy Valua constraints", function()
      local parsed = app:parse({ "--port", "8080", "production" })
      assert.equal(parsed.args.port, 8080)
      assert.equal(parsed.args.env, "production")
    end)

    it("rejects non-integer input for integer schema", function()
      assert.has_error(function()
        app:parse({ "--port", "not-a-number", "development" })
      end, "Validation failed")
    end)

    it("rejects values violating min_value or max_value constraint", function()
      assert.has_error(function()
        app:parse({ "--port", "0", "development" })
      end, "Validation failed")

      assert.has_error(function()
        app:parse({ "--port", "70000", "development" })
      end, "Validation failed")
    end)

    it("rejects invalid picklist value with structured issue", function()
      assert.has_error(function()
        app:parse({ "--port", "3000", "invalid-env" })
      end, "Validation failed")
    end)
  end)

end)
