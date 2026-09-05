local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 14 & 15: '--' Passthrough Delimiter and Exact Raw Preservation", function()

  local app = c.create({
    name = "tool",
    version = "1.0.0",

    c.root(c.node({
      c.flag("-v", "--verbose"),

      exec = c.node({
        c.flag("-d", "--debug"),

        build = c.node({
          c.flag("-f", "--force"),
          c.passthrough("forwarded"),
          c.run(function(ctx) return ctx end),
        }),
      }),
    })),
  })

  it("Invariant 14: '--' terminates option and subcommand recognition immediately", function()
    -- '-v', '--debug', 'build' appearing after '--' must NOT be parsed as options or commands
    local parsed = app:parse({ "exec", "build", "-f", "--", "-v", "--debug", "--unknown", "extra" })
    assert.equal(parsed.target_node.name, "build")
    assert.equal(parsed.args.force, true)
    -- verbose and debug were placed after '--', so they are false/unparsed
    assert.equal(parsed.args.verbose, false)
    assert.equal(parsed.args.debug, false)

    -- All tokens after '--' are in passthrough
    assert.same(parsed.passthrough, { "-v", "--debug", "--unknown", "extra" })
  end)

  it("Invariant 15: preserves raw tokens exactly without splitting, normalization, or modification", function()
    local raw_tokens = {
      "-Dfoo=bar",
      "--flag-with-dashes",
      "key: value with spaces",
      "-xvf",
      "\"quoted-string\"",
      "special-chars: $PATH ; && ||",
    }

    local argv = { "exec", "build", "--" }
    for _, tok in ipairs(raw_tokens) do
      table.insert(argv, tok)
    end

    local parsed = app:parse(argv)
    assert.same(parsed.passthrough, raw_tokens)
    assert.same(parsed.args.forwarded, raw_tokens)
  end)

  it("Section 23: populates declared c.passthrough(key) into ctx.args[key]", function()
    local parsed = app:parse({ "exec", "build", "--", "alpha", "beta", "gamma" })
    assert.same(parsed.args.forwarded, { "alpha", "beta", "gamma" })
    assert.same(parsed.passthrough, { "alpha", "beta", "gamma" })
  end)

  it("handles standalone '--' with no subsequent tokens", function()
    local parsed = app:parse({ "exec", "build", "--" })
    assert.same(parsed.passthrough, {})
    assert.same(parsed.args.forwarded, {})
  end)

  it("handles commands without '--' yielding empty passthrough list", function()
    local parsed = app:parse({ "exec", "build", "-f" })
    assert.same(parsed.passthrough, {})
    assert.is_nil(parsed.args.forwarded)
  end)

end)
