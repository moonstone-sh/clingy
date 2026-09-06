local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Interactive Subprocess Terminal Handoff (HOST-INV-09)", function()

  it("suspends host before interactive child execution and resumes on exit", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "spawn-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          local proc = ctx:spawn({
            argv = { "echo", "interactive-test" },
            mode = "interactive",
          })
          proc:wait()
          return "done"
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    -- Check that suspend and resume were recorded
    local has_suspend = false
    local has_resume = false
    for _, call in ipairs(rec.calls) do
      if call.method == "suspend" then
        has_suspend = true
        assert.equal(call.args[1].reason, "subprocess")
      elseif call.method == "resume" then
        has_resume = true
      end
    end

    assert.truthy(has_suspend, "host:suspend called for interactive subprocess")
    assert.truthy(has_resume, "host:resume called after interactive subprocess")
  end)

  it("does not suspend host for non-interactive (capture/inherit) subprocesses", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "capture-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          local proc = ctx:spawn({
            argv = { "echo", "capture-test" },
            mode = "capture",
          })
          proc:wait()
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    for _, call in ipairs(rec.calls) do
      assert.not_equal(call.method, "suspend", "non-interactive spawn does not suspend host")
    end
  end)

  it("strictly aborts interactive subprocess if host:suspend fails", function()
    local failing_host = c.failing_host({ fail_on = { suspend = "Failed to release TUI terminal raw mode" } })
    local child_executed = false

    local app = c.create({
      name = "fail-suspend-app",
      presentation = failing_host,
      c.root(c.node({
        c.run(function(ctx)
          local proc = ctx:spawn({
            argv = { "echo", "should-not-run" },
            mode = "interactive",
          })
          proc:wait()
          child_executed = true
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 1, "app:run fails when suspend fails before interactive spawn")
    assert.falsy(child_executed, "child process execution was aborted")
  end)

end)
