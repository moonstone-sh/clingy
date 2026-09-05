local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Declarative Table DSL Syntax Specifications (Section 3, 45)", function()

  describe("c.node and c.root constructors", function()
    it("creates a command node with declarations and string-keyed child nodes", function()
      local node = c.node({
        c.flag("-v", "--verbose"),
        c.arg("target", v.string()),

        deploy = c.node({
          c.flag("--prod"),
        }, {
          description = "Deploy command",
          aliases = { "d" },
        }),
      }, {
        description = "Root node",
      })

      assert.equal(node._tag, "node")
      assert.equal(#node.declarations, 2)
      assert.truthy(node.children.deploy)
      assert.equal(node.children.deploy._tag, "node")
      assert.equal(node.children.deploy.metadata.description, "Deploy command")
      assert.same(node.children.deploy.metadata.aliases, { "d" })
    end)

    it("c.root validates that it wraps a c.node", function()
      local node = c.node({})
      local root = c.root(node)
      assert.equal(root._tag, "root")
      assert.equal(root.node, node)

      assert.has_error(function()
        c.root("not-a-node")
      end)
    end)
  end)

  describe("c.group and c.inherit constructors", function()
    it("creates a reusable group of declarations", function()
      local grp = c.group({
        c.flag("-q", "--quiet"),
        c.flag("--json"),
      })

      assert.equal(grp._tag, "group")
      assert.equal(#grp.declarations, 2)
    end)

    it("creates an explicit inheritance wrapper", function()
      local inh = c.inherit(
        c.flag("-v", "--verbose"),
        c.interspersed()
      )

      assert.equal(inh._tag, "inherit")
      assert.equal(#inh.items, 2)
    end)
  end)

  describe("c.arg, c.option, and c.flag declarations", function()
    it("creates positional arg with default 1..1 cardinality", function()
      local a = c.arg("source", v.string())
      assert.equal(a._tag, "declaration")
      assert.equal(a.kind, "arg")
      assert.equal(a.name, "source")
      assert.equal(a.result_key, "source")
      assert.equal(a.occurrence.min, 1)
      assert.equal(a.occurrence.max, 1)
      assert.equal(a.aggregate, "scalar")
    end)

    it("creates option deriving key from longest long-form alias", function()
      local opt = c.option("-j", "--jobs", v.integer())
      assert.equal(opt._tag, "declaration")
      assert.equal(opt.kind, "option")
      assert.same(opt.names, { "-j", "--jobs" })
      assert.equal(opt.result_key, "jobs")
      assert.equal(opt.occurrence.min, 0)
      assert.equal(opt.occurrence.max, 1)
      assert.equal(opt.values.min, 1)
      assert.equal(opt.values.max, 1)
      assert.equal(opt.aggregate, "scalar")
    end)

    it("creates option with only short flag deriving short key", function()
      local opt = c.option("-k", v.string())
      assert.equal(opt.result_key, "k")
    end)

    it("creates boolean flag with default false and 0..0 values", function()
      local fl = c.flag("-f", "--force")
      assert.equal(fl._tag, "declaration")
      assert.equal(fl.kind, "flag")
      assert.equal(fl.result_key, "force")
      assert.equal(fl.default, false)
      assert.equal(fl.values.min, 0)
      assert.equal(fl.values.max, 0)
    end)
  end)

  describe("Cardinality modifiers: c.optional, c.required, c.repeated", function()
    it("c.optional sets min = 0", function()
      local a = c.optional(c.arg("profile", v.string()))
      assert.equal(a.occurrence.min, 0)
      assert.equal(a.occurrence.max, 1)
    end)

    it("c.required sets min = 1", function()
      local opt = c.required(c.option("-p", "--port", v.integer()))
      assert.equal(opt.occurrence.min, 1)
      assert.equal(opt.occurrence.max, 1)
    end)

    it("c.repeated sets max = nil and aggregate = 'array'", function()
      local opt = c.repeated(c.option("-H", "--header", v.string()))
      assert.equal(opt.occurrence.min, 0)
      assert.is_nil(opt.occurrence.max)
      assert.equal(opt.aggregate, "array")
    end)
  end)

  describe("Parser modes, capabilities, and handlers", function()
    it("creates parser mode tags", function()
      assert.equal(c.interspersed()._tag, "parser_mode")
      assert.equal(c.interspersed().mode, "interspersed")

      assert.equal(c.leading()._tag, "parser_mode")
      assert.equal(c.leading().mode, "leading")

      assert.equal(c.ordered()._tag, "parser_mode")
      assert.equal(c.ordered().mode, "ordered")

      assert.equal(c.short_clusters()._tag, "short_clusters")
      assert.equal(c.passthrough("raw")._tag, "passthrough")
      assert.equal(c.passthrough("raw").key, "raw")
    end)

    it("creates run handler and signals tags", function()
      local fn = function(ctx) end
      local run_tag = c.run(fn)
      assert.equal(run_tag._tag, "run")
      assert.equal(run_tag.handler, fn)

      local sigs = { interrupt = function() end }
      local sig_tag = c.signals(sigs)
      assert.equal(sig_tag._tag, "signals")
      assert.equal(sig_tag.handlers, sigs)
    end)
  end)

end)
