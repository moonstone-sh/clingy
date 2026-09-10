local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it, assert = h.describe, h.it, h.assert

describe("table declarations and forms", function()
  it("does not expose removed declaration wrappers", function()
    for _, name in ipairs({ "define", "compose", "label", "separator", "required", "repeated", "complete", "end", "end_", "c" }) do
      assert.is_nil(c[name], "removed c." .. name)
    end
  end)

  it("parses attached, detached, and repeated named values", function()
    local app = c.create({ name = "tool", root = c.node({
      c.option({ key = "define", aliases = { "-D", "--define" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }),
    }) })
    local parsed = app:parse({ "-D=one", "--define", "two", "-v" })
    assert.same(parsed.args.define, { "one", "two" })
    assert.equal(parsed.args.verbose, true)
  end)

  it("rejects a repeated default option", function()
    local app = c.create({ name = "tool", root = c.node({
      c.option({ key = "output", aliases = { "-o", "--output" }, value = { schema = v.string() } }),
    }) })
    assert.has_error(function() app:parse({ "-o", "one", "-o", "two" }) end, "at most 1")
  end)

  it("validates only the selected form choice", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "value", form = c.choice({
        c.sequence({ c.literal({ text = "i:" }), c.capture({ key = "item", schema = v.integer() }) }),
        c.sequence({ c.literal({ text = "s:" }), c.capture({ key = "item", schema = v.string() }) }),
      }) }),
    }) })
    assert.equal(app:parse({ "s:abc" }).args.value.item, "abc")
  end)

  it("completes an active form capture as a valid argv fragment", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "dev", form = c.sequence({
        c.literal({ text = "dev:" }),
        c.capture({ key = "user", schema = v.picklist({ "adam", "alice" }) }),
      }) }),
    }) })
    local response = app:complete({ words = { "tool", "dev:a" }, cword = 2 })
    assert.equal(response.candidates[1].value, "dev:adam")
    assert.equal(response.candidates[2].value, "dev:alice")
  end)

  it("uses declaration-local completion for positional arguments", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "path", schema = v.string(), complete = c.values({ "alpha" }) }),
    }) })
    local response = app:complete({ words = { "tool", "a" }, cword = 2 })
    assert.equal(response.candidates[1].value, "alpha")
  end)

  it("completes a capture after c.next_token()", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "dev", form = c.sequence({
        c.literal({ text = "dev:" }),
        c.capture({ key = "user", schema = v.string() }),
        c.next_token(),
        c.capture({ key = "mode", schema = v.picklist({ "inherit", "local" }) }),
      }) }),
    }) })
    local response = app:complete({ words = { "tool", "dev:alice", "i" }, cword = 3 })
    assert.equal(response.candidates[1].value, "inherit")
  end)

  it("tracks completion through multiple token boundaries and later arguments", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "spec", form = c.sequence({
        c.literal({ text = "dev:" }),
        c.capture({ key = "user", schema = v.string(), complete = c.values({ "alice" }) }),
        c.next_token(),
        c.literal({ text = "org:" }),
        c.capture({ key = "org", schema = v.string(), complete = c.values({ "moonstone" }) }),
        c.next_token(),
        c.capture({ key = "mode", schema = v.string(), complete = c.values({ "inherit" }) }),
      }) }),
      c.arg({ key = "path", schema = v.string(), complete = c.file({ extensions = { "luax" } }) }),
    }) })

    local first_literal = app:complete({ words = { "tool", "de" }, cword = 2 })
    assert.equal(first_literal.candidates[1].value, "dev:")
    local second_literal = app:complete({ words = { "tool", "dev:alice", "or" }, cword = 3 })
    assert.equal(second_literal.candidates[1].value, "org:")
    local org = app:complete({ words = { "tool", "dev:alice", "org:m" }, cword = 3 })
    assert.equal(org.candidates[1].value, "org:moonstone")
    local mode = app:complete({ words = { "tool", "dev:alice", "org:moonstone", "i" }, cword = 4 })
    assert.equal(mode.candidates[1].value, "inherit")
    local path = app:complete({ words = { "tool", "dev:alice", "org:moonstone", "inherit", "file.lu" }, cword = 5 })
    assert.equal(path.filesystem.kind, "file")
    assert.equal(path.filesystem.extensions[1], "luax")
  end)

  it("preserves attached and form prefixes for filesystem completion", function()
    local app = c.create({ name = "tool", root = c.node({
      c.option({ key = "config", aliases = { "--config" }, complete = c.file({ extensions = { "luax" } }) }),
      c.arg({ key = "source", form = c.sequence({
        c.literal({ text = "argument:" }),
        c.capture({ key = "path", schema = v.string(), complete = c.file({ extensions = { "luax" } }) }),
      }) }),
    }) })
    local attached = app:complete({ words = { "tool", "--config=src/ma" }, cword = 2 })
    assert.equal(attached.replace_prefix, "--config=")
    assert.equal(attached.filesystem.kind, "file")
    local formed = app:complete({ words = { "tool", "argument:src/ma" }, cword = 2 })
    assert.equal(formed.replace_prefix, "argument:")
    assert.equal(formed.filesystem.extensions[1], "luax")
  end)

  it("completes every compatible literal branch of a form choice", function()
    local app = c.create({ name = "tool", root = c.node({
      c.arg({ key = "target", form = c.choice({
        c.sequence({ c.literal({ text = "dev:database=" }), c.capture({ key = "value", schema = v.string() }) }),
        c.sequence({ c.literal({ text = "dev:org=" }), c.capture({ key = "value", schema = v.string() }) }),
        c.sequence({ c.literal({ text = "prod:user=" }), c.capture({ key = "value", schema = v.string() }) }),
      }) }),
    }) })
    local response = app:complete({ words = { "tool", "dev:" }, cword = 2 })
    assert.equal(response.candidates[1].value, "dev:database=")
    assert.equal(response.candidates[2].value, "dev:org=")
  end)

  it("rejects malformed table aliases", function()
    assert.has_error(function()
      c.flag({ key = "bad", aliases = { "not-an-option" } })
    end, "not a usable option")
  end)

  it("infers LuaLS context fields from table declarations", function()
    local plugin = require("luals.plugin")
    local transformed = plugin.process_text("", [[
local c = require("clingy")
local v = require("valua")
return c.node({
  c.arg({ key = "name", schema = v.string() }),
  c.option({ key = "define", aliases = { "-D" }, value = { schema = v.integer() }, occurs = { min = 0, max = "many" } }),
  c.flag({ key = "verbose", aliases = { "-v" } }),
  c.run(function(ctx) return ctx.args end),
})
]])
    assert.truthy(transformed:find("define: %(integer%)%[%]%|nil"))
    assert.truthy(transformed:find("name: string"))
    assert.truthy(transformed:find("verbose: boolean"))
  end)
end)
