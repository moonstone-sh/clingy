local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Section 47: End-to-End Meteorite CLI Execution Example", function()

  local Profile = v.describe(
    v.picklist({
      "development",
      "production",
      "test",
    }),
    "Project profile"
  )

  local Define = v.describe(
    v.string(),
    "Build-time definition"
  )

  local last_execution = nil

  local app = c.create({
    name = "meteorite",
    version = "0.1.0",

    c.root(c.node({
      c.inherit(
        c.interspersed(),
        c.short_clusters(),

        c.flag("-v", "--verbose"),
        c.flag("-q", "--quiet")
      ),

      init = c.node({
        c.inherit(
          c.flag("--json")
        ),

        c.arg("profile", Profile),

        instant = c.node({
          c.flag("-n", "--now"),

          c.signals({
            interrupt = function(ctx)
              return ctx:confirm("Abort initialization?")
            end,

            terminate = function()
              return c.signal.shutdown()
            end,
          }),

          c.run(function(ctx)
            last_execution = {
              command = "init.instant",
              args = ctx.args,
              route = ctx.route,
            }
            return { status = "initialized", profile = ctx.args.profile }
          end),
        }),
      }),

      build = c.node({
        c.repeated(
          c.option("-D", "--define", Define)
        ),

        c.run(function(ctx)
          last_execution = {
            command = "build",
            args = ctx.args,
            route = ctx.route,
          }
          return { status = "built", defines = ctx.args.define }
        end),
      }),

      legacy = c.node({
        c.ordered(),

        c.flag("--prepare"),
        c.arg("source", v.string()),
        c.flag("--commit"),
        c.arg("destination", v.string()),

        c.run(function(ctx)
          last_execution = {
            command = "legacy",
            args = ctx.args,
            route = ctx.route,
          }
          return { status = "migrated", src = ctx.args.source, dst = ctx.args.destination }
        end),
      }),
    })),
  })

  it("executes multi-segment init instant with cluster -vn: meteorite init development instant -vn", function()
    last_execution = nil
    local exit_code = app:run({ "init", "development", "instant", "-vn" }, { capture = true })

    assert.equal(exit_code, 0)
    assert.truthy(last_execution)
    assert.equal(last_execution.command, "init.instant")
    assert.equal(last_execution.args.profile, "development")
    assert.equal(last_execution.args.verbose, true)
    assert.equal(last_execution.args.now, true)
    assert.equal(last_execution.args.quiet, false)
    assert.equal(last_execution.args.json, false)
  end)

  it("executes init instant with --json flag and long forms", function()
    last_execution = nil
    local exit_code = app:run({ "init", "production", "instant", "--now", "--verbose", "--json" }, { capture = true })

    assert.equal(exit_code, 0)
    assert.truthy(last_execution)
    assert.equal(last_execution.args.profile, "production")
    assert.equal(last_execution.args.now, true)
    assert.equal(last_execution.args.verbose, true)
    assert.equal(last_execution.args.json, true)
  end)

  it("fails execution when profile violates Valua picklist schema", function()
    last_execution = nil
    local exit_code = app:run({ "init", "nonexistent_profile", "instant" }, { capture = true })

    assert.equal(exit_code, 1)
    assert.is_nil(last_execution)
  end)

  it("executes build command with repeated -D and --define options", function()
    last_execution = nil
    local exit_code = app:run({ "build", "-D", "FOO=1", "-D", "BAR=2", "--define", "BAZ=3" }, { capture = true })

    assert.equal(exit_code, 0)
    assert.truthy(last_execution)
    assert.equal(last_execution.command, "build")
    assert.same(last_execution.args.define, { "FOO=1", "BAR=2", "BAZ=3" })
  end)

  it("executes legacy command strictly adhering to ordered grammar mode", function()
    last_execution = nil
    local exit_code = app:run({ "legacy", "--prepare", "input.txt", "--commit", "output.txt" }, { capture = true })

    assert.equal(exit_code, 0)
    assert.truthy(last_execution)
    assert.equal(last_execution.command, "legacy")
    assert.equal(last_execution.args.prepare, true)
    assert.equal(last_execution.args.source, "input.txt")
    assert.equal(last_execution.args.commit, true)
    assert.equal(last_execution.args.destination, "output.txt")
  end)

  it("allows legacy command to skip optional --prepare flag", function()
    last_execution = nil
    local exit_code = app:run({ "legacy", "input.txt", "--commit", "output.txt" }, { capture = true })

    assert.equal(exit_code, 0)
    assert.truthy(last_execution)
    assert.equal(last_execution.args.prepare, false)
    assert.equal(last_execution.args.source, "input.txt")
    assert.equal(last_execution.args.commit, true)
    assert.equal(last_execution.args.destination, "output.txt")
  end)

  it("rejects legacy command when flags violate declared order", function()
    last_execution = nil
    local exit_code = app:run({ "legacy", "input.txt", "output.txt", "--commit" }, { capture = true })

    assert.equal(exit_code, 1)
    assert.is_nil(last_execution)
  end)

  it("rejects unknown commands and options gracefully with exit code 1", function()
    local code1 = app:run({ "unknown_command" }, { capture = true })
    assert.equal(code1, 1)

    local code2 = app:run({ "build", "--bogus-flag" }, { capture = true })
    assert.equal(code2, 1)
  end)

end)
