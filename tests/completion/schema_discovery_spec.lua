--[[
  tests/completion/schema_discovery_spec.lua
  Schema-derived completion discovery: Valua picklist/literal, third-party adapters,
  and precedence rules.
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")
local comp_mod = require("clingy.completion")
local discovery = comp_mod.discovery

local describe, it = h.describe, h.it
local assert = h.assert

describe("Schema-Derived Completion Discovery", function()

  describe("Valua Schema Discovery (Picklist & Literal)", function()
    it("discovers string picklist choices automatically", function()
      local schema = v.picklist({ "development", "staging", "production" })
      local provider = discovery.discover_provider(schema)
      assert.not_nil(provider, "derived provider from picklist")
      local resp = provider:resolve(comp_mod.context.create())
      assert.equal(#resp.candidates, 3)
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["development"])
      assert.truthy(vals["staging"])
      assert.truthy(vals["production"])
    end)

    it("discovers numeric picklist choices as string candidates", function()
      local schema = v.picklist({ 80, 443, 8080 })
      local provider = discovery.discover_provider(schema)
      assert.not_nil(provider, "derived provider from numeric picklist")
      local resp = provider:resolve(comp_mod.context.create())
      assert.equal(#resp.candidates, 3)
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["80"])
      assert.truthy(vals["443"])
      assert.truthy(vals["8080"])
    end)

    it("discovers singleton choice from v.literal", function()
      local schema = v.literal("active")
      local provider = discovery.discover_provider(schema)
      assert.not_nil(provider, "derived provider from literal")
      local resp = provider:resolve(comp_mod.context.create())
      assert.equal(#resp.candidates, 1)
      assert.equal(resp.candidates[1].value, "active")
    end)

    it("returns nil provider for unconstrained schema (v.string, v.integer)", function()
      local p_str = discovery.discover_provider(v.string())
      assert.is_nil(p_str, "unconstrained string yields no automatic values provider")

      local p_int = discovery.discover_provider(v.integer())
      assert.is_nil(p_int, "unconstrained integer yields no automatic values provider")
    end)
  end)

  describe("Third-Party Schema Adapter Picklist Discovery", function()
    -- Register a mock custom third-party schema adapter
    c.schema_adapter({
      name = "custom_enum_validator",
      match = function(schema)
        return type(schema) == "table" and schema["~standard"] and schema["~standard"].vendor == "custom_enum"
      end,
      inspect = function(schema)
        return {
          kind = "picklist",
          options = schema.allowed_values or {},
        }
      end,
    })

    local custom_schema = {
      allowed_values = { "fast", "balanced", "thorough" },
      ["~standard"] = {
        version = 1,
        vendor = "custom_enum",
        validate = function(val) return { value = val } end,
      },
    }

    it("derives completion candidates through custom schema adapter", function()
      local provider = discovery.discover_provider(custom_schema)
      assert.not_nil(provider, "derived provider via custom adapter")
      local resp = provider:resolve(comp_mod.context.create())
      assert.equal(#resp.candidates, 3)
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["fast"])
      assert.truthy(vals["balanced"])
      assert.truthy(vals["thorough"])
    end)

    it("works end-to-end inside an App with custom adapter", function()
      local app = c.create({
        name = "custom_cli",
        c.root(c.node({
          c.option("-m", "--mode", custom_schema),
          c.run(function() end),
        })),
      })

      local resp = app:complete({ "custom_cli", "--mode", "" })
      assert.equal(#resp.candidates, 3)
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["fast"])
      assert.truthy(vals["balanced"])
      assert.truthy(vals["thorough"])
    end)
  end)

  describe("Precedence: Explicit Provider Overrides Schema Discovery", function()
    local picklist_schema = v.picklist({ "one", "two", "three" })

    it("explicit c.complete overrides schema choices in App execution", function()
      local app = c.create({
        name = "prec_cli",
        c.root(c.node({
          c.complete(
            c.values("alpha", "beta"),
            c.option("-e", "--env", picklist_schema)
          ),
          c.run(function() end),
        })),
      })

      local resp = app:complete({ "prec_cli", "--env", "" })
      assert.equal(#resp.candidates, 2)
      assert.equal(resp.candidates[1].value, "alpha")
      assert.equal(resp.candidates[2].value, "beta")
    end)

    it("c.none() overrides schema choices with zero candidates", function()
      local app = c.create({
        name = "none_cli",
        c.root(c.node({
          c.complete(
            c.none(),
            c.option("-k", "--key", picklist_schema)
          ),
          c.run(function() end),
        })),
      })

      local resp = app:complete({ "none_cli", "--key", "" })
      assert.equal(#resp.candidates, 0)
      assert.truthy(resp:has_directive(comp_mod.response.DIRECTIVE.NO_FILES))
    end)
  end)

end)
