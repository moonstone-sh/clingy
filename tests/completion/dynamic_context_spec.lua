--[[
  tests/completion/dynamic_context_spec.lua
  Dynamic Completion Provider & Context Isolation:
  Verifies that dynamic completion callbacks receive parsed preceding arguments,
  context metadata, and that callback errors or stdout/stderr prints are strictly contained.
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")
local comp_mod = require("clingy.completion")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Dynamic Completion Provider & Context Sandbox", function()

  describe("Context Inspection: Preceding Parsed Arguments & Metadata", function()
    it("dynamic provider receives preceding parsed options and positionals", function()
      local captured_ctx = nil

      local dyn_provider = c.dynamic(function(ctx)
        captured_ctx = ctx
        if ctx.args.region == "us-west" then
          return { "cluster-west-1", "cluster-west-2" }
        elseif ctx.args.region == "eu-central" then
          return { "cluster-eu-1", "cluster-eu-2" }
        end
        return { "cluster-default" }
      end)

      local app = c.create({
        name = "cloud",
        c.root(c.node({
          deploy = c.node({
            c.option("-r", "--region", v.string()),
            c.complete(dyn_provider, c.arg("cluster")),
            c.run(function() end),
          }),
        })),
      })

      -- Case A: region = us-west
      local resp_west = app:complete({ "cloud", "deploy", "--region", "us-west", "" })
      assert.equal(#resp_west.candidates, 2)
      assert.equal(resp_west.candidates[1].value, "cluster-west-1")
      assert.equal(resp_west.candidates[2].value, "cluster-west-2")

      assert.not_nil(captured_ctx)
      assert.equal(captured_ctx.args.region, "us-west")
      assert.equal(captured_ctx.prefix, "")
      assert.equal(type(captured_ctx.words), "table")
      assert.truthy(captured_ctx.cword >= 1)
      assert.not_nil(captured_ctx.target_node)
      assert.truthy(#captured_ctx.route >= 1)
      assert.not_nil(captured_ctx.cwd)
      assert.not_nil(captured_ctx.env)

      -- Case B: region = eu-central
      local resp_eu = app:complete({ "cloud", "deploy", "--region", "eu-central", "cluster-eu-1" })
      assert.equal(#resp_eu.candidates, 1)
      assert.equal(resp_eu.candidates[1].value, "cluster-eu-1")
    end)

    it("dynamic provider filters candidates by ctx.prefix automatically", function()
      local p = c.dynamic(function(ctx)
        return { "alpha", "alpine", "beta", "gamma" }
      end)

      local ctx = comp_mod.context.create({ prefix = "al" })
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 2)
      assert.equal(resp.candidates[1].value, "alpha")
      assert.equal(resp.candidates[2].value, "alpine")
    end)
  end)

  describe("Sterile Sandbox Failure Containment & I/O Protection", function()
    it("safely catches lua runtime error in callback and returns 0 candidates", function()
      local broken_provider = c.dynamic(function(ctx)
        error("Catastrophic database connection failure in completion hook!")
      end)

      local ctx = comp_mod.context.create()
      local resp = nil
      assert.no_error(function()
        resp = broken_provider:resolve(ctx)
      end, "broken provider must not raise error to caller")

      assert.not_nil(resp)
      assert.equal(#resp.candidates, 0, "error results in 0 candidates")
    end)

    it("suppresses all stdout/stderr pollution from rogue print() and io.write() inside callback", function()
      local output_leaked = false

      local noisy_provider = c.dynamic(function(ctx)
        print("ROGUE_PRINT_OUTPUT_THAT_MUST_BE_SUPPRESSED")
        io.write("ROGUE_IO_WRITE_OUTPUT\n")
        io.stdout:write("ROGUE_STDOUT_WRITE\n")
        io.stderr:write("ROGUE_STDERR_WRITE\n")
        return { "clean_candidate" }
      end)

      local ctx = comp_mod.context.create()
      local resp = noisy_provider:resolve(ctx)
      assert.equal(#resp.candidates, 1)
      assert.equal(resp.candidates[1].value, "clean_candidate")
    end)

    it("gracefully handles nil or non-table returns from dynamic callback", function()
      local nil_provider = c.dynamic(function(ctx)
        return nil
      end)

      local ctx = comp_mod.context.create()
      local resp = nil_provider:resolve(ctx)
      assert.not_nil(resp)
      assert.equal(#resp.candidates, 0)
    end)
  end)

end)
