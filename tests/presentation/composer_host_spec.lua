local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Composer Presentation Host Modes & Options (HOST-INV-02, 13, 14, 15, 16)", function()

  it("operates in fancy mode when is_tty is true", function()
    local comp = c.composer({ mode = "fancy", capture = true, is_tty = true })
    local app = c.create({
      name = "fancy-app",
      presentation = comp,
      c.root(c.node({
        c.run(function(ctx)
          ctx:log("info", "Starting fancy demo")
          ctx:progress("task1", 50, "Halfway done")
          ctx:milestone("Step 1 complete")
          ctx:result("Success payload")
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(#comp.captured_lines > 0)

    local joined = table.concat(comp.captured_lines, "\n")
    assert.truthy(joined:find("%[INFO%] Starting fancy demo"))
    assert.truthy(joined:find("%[ 50%%%] Halfway done"))
    assert.truthy(joined:find("==> Step 1 complete"))
    assert.truthy(joined:find("Success payload"))
  end)

  it("operates in plain mode with semantic reduction (zero ANSI, no tick spam)", function()
    local comp = c.composer({ mode = "plain", capture = true })
    local app = c.create({
      name = "plain-app",
      presentation = comp,
      c.root(c.node({
        c.run(function(ctx)
          ctx:log("info", "Compiling assets")
          ctx:progress("comp", 10, "Tick 10")
          ctx:progress("comp", 20, "Tick 20")
          ctx:progress("comp", 30, "Tick 30")
          ctx:milestone("Compilation finished")
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    local joined = table.concat(comp.captured_lines, "\n")
    assert.truthy(joined:find("%[INFO%] Compiling assets"))
    assert.truthy(joined:find("Tick 10"))
    -- Tick 20 and 30 should be suppressed in plain mode semantic reduction
    assert.falsy(joined:find("Tick 20"))
    assert.falsy(joined:find("Tick 30"))
    assert.truthy(joined:find("=> Compilation finished"))
  end)

  it("operates in quiet mode, suppressing progress and normal logs", function()
    local comp = c.composer({ mode = "quiet", capture = true })
    local app = c.create({
      name = "quiet-app",
      presentation = comp,
      c.root(c.node({
        c.run(function(ctx)
          ctx:log("info", "Hidden info log")
          ctx:progress("task", 50, "Hidden progress")
          ctx:log("error", "Visible error log")
          ctx:result("Final result output")
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    local joined = table.concat(comp.captured_lines, "\n")
    assert.falsy(joined:find("Hidden info log"))
    assert.falsy(joined:find("Hidden progress"))
    assert.truthy(joined:find("Visible error log"))
    assert.truthy(joined:find("Final result output"))
  end)

  it("operates in ndjson mode and accepts 'json' alias for backward compatibility", function()
    local comp_ndjson = c.composer({ mode = "ndjson", capture = true })
    local comp_json = c.composer({ mode = "json", capture = true })

    assert.equal(comp_ndjson.mode, "ndjson")
    assert.equal(comp_json.mode, "ndjson")

    local app = c.create({
      name = "json-app",
      presentation = comp_ndjson,
      c.root(c.node({
        c.run(function(ctx)
          ctx:log("info", "Structured telemetry event")
          ctx:result({ status = "ready", code = 200 })
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    -- Assert each line is valid JSON
    for _, line in ipairs(comp_ndjson.captured_lines) do
      assert.truthy(line:sub(1, 1) == "{" and line:sub(-1) == "}")
      assert.truthy(line:find('"protocol":"clingy.events.v1"'))
    end
  end)

  it("supports backward-compatible opts.composer_mode and ctx.composer alias", function()
    local comp = c.composer({ capture = true })
    local app = c.create({
      name = "compat-app",
      c.root(c.node({
        c.run(function(ctx)
          assert.truthy(ctx.presentation, "ctx.presentation exists")
          assert.truthy(ctx.composer, "ctx.composer alias exists")
          assert.equal(ctx.presentation, ctx.composer, "ctx.composer is an alias to ctx.presentation")
          ctx:log("info", "Compatibility verified")
        end),
      })),
    })

    local exit_code = app:run({}, { presentation = comp, composer_mode = "quiet" })
    assert.equal(exit_code, 0)
    assert.equal(comp.mode, "quiet")
  end)

end)
