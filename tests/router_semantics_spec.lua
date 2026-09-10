local h = require("tests.harness")
local c = require("clingy")
local partial = require("clingy.completion.partial_parser")

local describe, it, assert = h.describe, h.it, h.assert

local function candidate_values(response)
  local values = {}
  for _, candidate in ipairs(response.candidates) do
    values[#values + 1] = candidate.value
  end
  return values
end

describe("fixed-prefix command routing", function()
  it("uses root = c.node and no longer exposes c.root", function()
    assert.is_nil(c.root)
    local app = c.create({
      name = "tool",
      root = c.node({ c.run(function() end) }),
    })
    assert.equal(app:parse({}).target_node.id, "root")
  end)

  it("requires a parent positional prefix before traversing a child edge", function()
    local app = c.create({
      name = "tool",
      root = c.node({
        c.arg({ key = "profile", complete = c.values({ "development" }) }),
        build = c.node({}, { description = "Build the profile", aliases = { "b" } }),
      }),
    })

    assert.has_error(function() app:parse({ "build" }) end,
      "Missing required argument 'profile' before command 'build'")
    assert.equal(app:parse({ "development", "build" }).target_node.id, "root.build")
    assert.equal(app:parse({ "development", "b" }).target_node.id, "root.build")

    local before_prefix = app:complete({ words = { "tool", "b" }, cword = 2 })
    assert.same(candidate_values(before_prefix), {})

    local after_prefix = app:complete({ words = { "tool", "development", "b" }, cword = 3 })
    assert.equal(after_prefix.candidates[1].value, "build")

    local alias_state = partial.parse_partial(app._graph, { "tool", "development", "b", "" }, 4)
    assert.equal(alias_state.current_node.id, "root.build")
  end)

  it("rejects optional and repeated positionals on a routing node", function()
    assert.has_error(function()
      c.create({
        name = "tool",
        root = c.node({
          c.arg({ key = "scope", occurs = { min = 0, max = 1 } }),
          build = c.node({}),
        }),
      })
    end, "must occur exactly once before routing")

    assert.has_error(function()
      c.create({
        name = "tool",
        root = c.node({
          c.arg({ key = "scope", occurs = { min = 1, max = "many" } }),
          build = c.node({}),
        }),
      })
    end, "must occur exactly once before routing")
  end)

  it("lets -- close routing so a child spelling can be positional data", function()
    local app = c.create({
      name = "tool",
      root = c.node({
        c.arg({ key = "subject" }),
        build = c.node({}),
        c.run(function() end),
      }),
    })

    local parsed = app:parse({ "--", "build" })
    assert.equal(parsed.target_node.id, "root")
    assert.equal(parsed.args.subject, "build")

    local state = partial.parse_partial(app._graph, { "tool", "--", "" }, 3)
    assert.equal(state.focus, partial.FOCUS.POSITIONAL)
  end)

  it("renders a required command honestly in help", function()
    local app = c.create({
      name = "tool",
      root = c.node({
        c.arg({ key = "profile" }),
        build = c.node({}),
      }),
    })
    assert.matches(app:help(), "tool <PROFILE> <COMMAND>")
  end)
end)
