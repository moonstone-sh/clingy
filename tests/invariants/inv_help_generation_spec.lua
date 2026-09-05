local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant: Help Generation & Ownership UX (Section 30, 31)", function()

  local app = c.create({
    name = "meteorite",
    version = "1.0.0",
    description = "Moonstone HTTP framework and CLI engine",
    c.root(c.node({
      c.inherit(
        c.flag("-v", "--verbose"),
        c.flag("-q", "--quiet")
      ),
      c.flag("--json"),

      init = c.node({
        c.arg("profile", v.picklist({ "development", "production", "test" })),
        c.option("-t", "--template", v.string()),

        instant = c.node({
          c.flag("-n", "--now"),
          c.run(function(ctx) return ctx.args end),
        }, {
          description = "Instantly scaffold project",
          aliases = { "inst" },
        }),
      }, {
        description = "Initialize a new project",
      }),
    })),
  })

  it("generates structured help for root command", function()
    local help_text = app:help()
    assert.truthy(help_text)
    assert.matches(help_text, "Moonstone HTTP framework and CLI engine")
    assert.matches(help_text, "Usage:%s+meteorite %[OPTIONS%] %[COMMAND%]")
    assert.matches(help_text, "%-v, %-%-verbose")
    assert.matches(help_text, "%-q, %-%-quiet")
    assert.matches(help_text, "Commands:")
    assert.matches(help_text, "init%s+Initialize a new project")
  end)

  it("generates structured help for subcommand distinguishing local vs global options", function()
    local help_text = app:help("init")
    assert.truthy(help_text)
    assert.matches(help_text, "Initialize a new project")
    assert.matches(help_text, "Usage:%s+meteorite init %[OPTIONS%] <PROFILE> %[COMMAND%]")
    assert.matches(help_text, "Arguments:")
    assert.matches(help_text, "<PROFILE>%s+%[development|production|test%]")
    assert.matches(help_text, "Options:")
    assert.matches(help_text, "%-t, %-%-template <VALUE>")
    assert.matches(help_text, "Global Options:")
    assert.matches(help_text, "%-v, %-%-verbose.*%[inherited from root%]")
  end)

  it("generates structured help for nested leaf command with aliases", function()
    local help_text = app:help({ "init", "instant" })
    assert.truthy(help_text)
    assert.matches(help_text, "Instantly scaffold project")
    assert.matches(help_text, "Usage:%s+meteorite init instant %[OPTIONS%]")
    assert.matches(help_text, "Options:")
    assert.matches(help_text, "%-n, %-%-now")
  end)

end)
