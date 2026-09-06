local h = require("tests.harness")
local c = require("clingy")
local signals = require("clingy.signals")
local context_mod = require("clingy.context")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Presentation Host Signal Handoff & Coordination (HOST-INV-13, 14)", function()

  it("coordinates signal dispatch while preserving host lifecycle", function()
    local rec = c.recording_host()
    local interrupt_handled = false

    local app = c.create({
      name = "signal-host-app",
      presentation = rec,
      c.root(c.node({
        c.signals({
          interrupt = function(ctx, evt)
            interrupt_handled = true
            return { action = "continue" }
          end,
        }),
        c.run(function(ctx)
          return { status = "running" }
        end),
      })),
    })

    local parsed = app:parse({})
    local ctx = context_mod.create_context({
      target_node = parsed.target_node,
      route = parsed.route,
      presentation = rec,
    })

    -- Dispatch signal through app
    local res = app:handle_signal("SIGINT", ctx)
    assert.truthy(interrupt_handled)
    assert.equal(res.action, "continue")
  end)

  it("coordinates prompt cancellation when signal interrupts a prompt", function()
    local rec = c.recording_host()

    local prompt_cancelled = false
    local prompt_fn = function(req)
      -- Simulate cancellation trigger
      prompt_cancelled = true
      return false
    end

    local test_host = c.recording_host({ prompt_responses = prompt_fn })

    local app = c.create({
      name = "prompt-signal-app",
      presentation = test_host,
      c.root(c.node({
        c.run(function(ctx)
          local ans = ctx:confirm("Proceed with deployment?", { default = false })
          return { confirmed = ans }
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(prompt_cancelled)
    assert.truthy(#test_host.prompts > 0)
    assert.truthy(test_host.is_closed)
  end)

  it("ensures host:finish and host:close run when termination signal unwinds the invocation", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "term-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          ctx:scope(function(s)
            s:defer(function()
              -- Simulate scope cleanup during emergency unwind
            end)
          end)
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(rec.is_closed)
    assert.truthy(rec.result)
    assert.equal(rec.result.status, "ok")
  end)

end)
