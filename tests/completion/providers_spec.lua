--[[
  tests/completion/providers_spec.lua
  Standard Completion Providers: c.values, c.path, c.file, c.directory, c.none,
  directive flags, and explicit provider precedence.
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")
local comp_mod = require("clingy.completion")
local response = comp_mod.response
local discovery = comp_mod.discovery

local describe, it = h.describe, h.it
local assert = h.assert

describe("Completion Providers & Directives", function()

  describe("c.values Provider", function()
    it("supports vararg strings", function()
      local p = c.values("staging", "production", "development")
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 3)
      assert.equal(resp.candidates[1].value, "staging")
      assert.equal(resp.candidates[2].value, "production")
      assert.equal(resp.candidates[3].value, "development")
    end)

    it("supports table of strings", function()
      local p = c.values({ "eu-central-1", "us-east-1", "ap-southeast-1" })
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 3)
      assert.equal(resp.candidates[1].value, "eu-central-1")
    end)

    it("supports candidate tables with descriptions", function()
      local p = c.values({
        { value = "json", description = "JavaScript Object Notation" },
        { value = "yaml", description = "YAML Ain't Markup Language" },
        { value = "toml", description = "Tom's Obvious Minimal Language" },
      })
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 3)
      assert.equal(resp.candidates[1].value, "json")
      assert.equal(resp.candidates[1].description, "JavaScript Object Notation")
      assert.equal(resp.candidates[2].value, "yaml")
      assert.equal(resp.candidates[2].description, "YAML Ain't Markup Language")
    end)

    it("filters candidates by prefix inside provider resolution", function()
      local p = c.values("apple", "apricot", "banana", "cherry")
      local ctx = comp_mod.context.create({ prefix = "ap" })
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 2)
      assert.equal(resp.candidates[1].value, "apple")
      assert.equal(resp.candidates[2].value, "apricot")
    end)
  end)

  describe("Filesystem Providers & Directives", function()
    it("c.file sets FILENAMES directive", function()
      local p = c.file({ extensions = { "lua", "json" } })
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.truthy(resp:has_directive(response.DIRECTIVE.FILENAMES))
      assert.falsy(resp:has_directive(response.DIRECTIVE.DIRECTORIES))
      assert.falsy(resp:has_directive(response.DIRECTIVE.NO_FILES))
    end)

    it("c.directory sets DIRECTORIES directive", function()
      local p = c.directory()
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.truthy(resp:has_directive(response.DIRECTIVE.DIRECTORIES))
      assert.falsy(resp:has_directive(response.DIRECTIVE.FILENAMES))
    end)

    it("c.path sets FILENAMES directive", function()
      local p = c.path()
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.truthy(resp:has_directive(response.DIRECTIVE.FILENAMES))
    end)
  end)

  describe("Hard Suppression: c.none() Provider", function()
    it("c.none emits zero candidates and NO_FILES directive", function()
      local p = c.none()
      local ctx = comp_mod.context.create()
      local resp = p:resolve(ctx)
      assert.equal(#resp.candidates, 0)
      assert.truthy(resp:has_directive(response.DIRECTIVE.NO_FILES))
    end)
  end)

  describe("Explicit c.complete Precedence over Schema-Derived Choices", function()
    local schema = v.picklist({ "raw1", "raw2", "raw3" })

    it("explicit c.complete provider overrides schema discovery", function()
      local opt = c.complete(
        c.values("overrideA", "overrideB"),
        c.option("-o", "--opt", schema)
      )
      local resolved = discovery.resolve_binding_completion(opt)
      assert.not_nil(resolved)
      local ctx = comp_mod.context.create()
      local resp = resolved:resolve(ctx)
      assert.equal(#resp.candidates, 2)
      assert.equal(resp.candidates[1].value, "overrideA")
      assert.equal(resp.candidates[2].value, "overrideB")
    end)

    it("explicit c.none overrides schema discovery with hard suppression", function()
      local opt = c.complete(c.none(), c.option("-s", "--secret", schema))
      local resolved = discovery.resolve_binding_completion(opt)
      assert.not_nil(resolved)
      local ctx = comp_mod.context.create()
      local resp = resolved:resolve(ctx)
      assert.equal(#resp.candidates, 0)
      assert.truthy(resp:has_directive(response.DIRECTIVE.NO_FILES))
    end)
  end)

end)
