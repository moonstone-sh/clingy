local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 12: Compile-Time Conflict Detection and Shadowing Rejection", function()

  it("rejects duplicate option or flag alias on the same node", function()
    assert.has_error(function()
      c.create({
        name = "test-dup-alias",
        c.root(c.node({
          c.flag("-v", "--verbose"),
          c.flag("-v", "--verify"), -- Duplicate '-v'
        })),
      })
    end, "Duplicate option/flag alias '-v'")

    assert.has_error(function()
      c.create({
        name = "test-dup-long",
        c.root(c.node({
          c.flag("-v", "--verbose", "--common"),
          c.flag("-c", "--clean", "--common"), -- Duplicate '--common'
        })),
      })
    end, "Duplicate option/flag alias '--common'")
  end)

  it("rejects child flag/option that shadows an inherited flag/option (NO silent shadowing)", function()
    -- Shadowing long option name
    assert.has_error(function()
      c.create({
        name = "test-shadow-long",
        c.root(c.node({
          c.inherit(
            c.flag("-v", "--verbose")
          ),
          child = c.node({
            c.flag("-b", "--verbose"), -- Shadowing '--verbose'
          }),
        })),
      })
    end)

    -- Shadowing short flag
    assert.has_error(function()
      c.create({
        name = "test-shadow-short",
        c.root(c.node({
          c.inherit(
            c.flag("-v", "--verbose")
          ),
          child = c.node({
            c.flag("-v", "--verify"), -- Shadowing '-v'
          }),
        })),
      })
    end)
  end)

  it("rejects output-key collision on the same node", function()
    -- Key collision between dashed and underscored options
    assert.has_error(function()
      c.create({
        name = "test-key-collision",
        c.root(c.node({
          c.option("--target-env", v.string()), -- key: target_env
          c.option("--target_env", v.string()), -- key: target_env
        })),
      })
    end, "Output-key collision")

    -- Key collision between positional arg and option
    assert.has_error(function()
      c.create({
        name = "test-arg-opt-collision",
        c.root(c.node({
          c.arg("output", v.string()),       -- key: output
          c.option("-o", "--output", v.string()), -- key: output
        })),
      })
    end, "Output-key collision")
  end)

  it("rejects output-key collision along an executable route", function()
    assert.has_error(function()
      c.create({
        name = "test-route-key-collision",
        c.root(c.node({
          c.flag("-d", "--debug"), -- key: debug on root

          deploy = c.node({
            c.arg("debug", v.string()), -- key: debug on deploy
          }),
        })),
      })
    end, "Output-key collision along route")
  end)

  it("rejects duplicate command names or aliases among siblings", function()
    assert.has_error(function()
      c.create({
        name = "test-dup-child",
        c.root(c.node({
          init = c.node({}, { aliases = { "start" } }),
          start = c.node({}), -- Collides with init's alias 'start'
        })),
      })
    end, "Duplicate command")
  end)

end)
