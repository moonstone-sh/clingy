local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Presentation Host Error Containment (HOST-INV-12)", function()

  it("contains errors thrown by host:handle_event without crashing primary command handler", function()
    local failing_host = c.failing_host({ fail_on = { handle_event = "Network render socket timeout" } })
    local handler_completed = false

    local app = c.create({
      name = "err-contain-app",
      presentation = failing_host,
      root = c.node({
        c.run(function(ctx)
          -- Emitting log will trigger failing_host:handle_event which throws
          ctx:log("info", "This event will throw in host")
          ctx:progress("step", 50)
          handler_completed = true
          return { success = true }
        end),
      }),
    })

    local exit_code = app:run({})
    -- The primary command handler should have completed successfully despite presentation host event errors
    assert.truthy(handler_completed)
    assert.equal(exit_code, 0)
  end)

  it("contains errors thrown by host:finish or host:flush during scope unwind", function()
    local failing_host = c.failing_host({ fail_on = { finish = "Finish error", flush = "Flush error" } })
    local handler_ran = false

    local app = c.create({
      name = "finish-err-app",
      presentation = failing_host,
      root = c.node({
        c.run(function(ctx)
          handler_ran = true
          return { done = true }
        end),
      }),
    })

    local exit_code = app:run({})
    assert.truthy(handler_ran)
    assert.equal(exit_code, 0)
  end)

  it("preserves primary handler error and triggers host:finish with failed status", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "app-err-app",
      presentation = rec,
      root = c.node({
        c.run(function(ctx)
          error("Fatal database connection failure")
        end),
      }),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 1)
    assert.truthy(rec.result)
    assert.equal(rec.result.status, "failed")
    assert.equal(rec.result.exit_code, 1)
    assert.truthy(rec.is_closed)
  end)

end)
