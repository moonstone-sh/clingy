local h = require("tests.harness")
local c = require("clingy")
local signals = require("clingy.signals")
local context_mod = require("clingy.context")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 19: Distinct Signal Semantics (INT vs TERM)", function()

  describe("Signal identity preservation and normalization", function()
    it("preserves distinct normalized identities for SIGINT and SIGTERM", function()
      -- String signal forms
      assert.equal(signals.normalize("SIGINT"), "interrupt")
      assert.equal(signals.normalize("INT"), "interrupt")
      assert.equal(signals.normalize("interrupt"), "interrupt")

      assert.equal(signals.normalize("SIGTERM"), "terminate")
      assert.equal(signals.normalize("TERM"), "terminate")
      assert.equal(signals.normalize("terminate"), "terminate")

      assert.equal(signals.normalize("SIGHUP"), "hangup")
      assert.equal(signals.normalize("HUP"), "hangup")

      -- Invariant 19: INT and TERM are never collapsed
      assert.not_equal(signals.normalize("SIGINT"), signals.normalize("SIGTERM"))
    end)

    it("normalizes POSIX numeric signal values (2 = INT, 15 = TERM, 1 = HUP)", function()
      assert.equal(signals.normalize(2), "interrupt")
      assert.equal(signals.normalize(15), "terminate")
      assert.equal(signals.normalize(1), "hangup")
    end)
  end)

  describe("Signal policy dispatch (Section 34)", function()
    it("dispatches distinct handlers for interrupt and terminate on a node", function()
      local interrupt_called = false
      local terminate_called = false
      local received_int_event = nil
      local received_term_event = nil

      local app = c.create({
        name = "test-signals",
        c.root(c.node({
          worker = c.node({
            c.signals({
              interrupt = function(ctx, evt)
                interrupt_called = true
                received_int_event = evt
                return { action = "prompt" }
              end,

              terminate = function(ctx, evt)
                terminate_called = true
                received_term_event = evt
                return c.signal.shutdown({ grace_ms = 500 })
              end,
            }),

            c.run(function(ctx) return ctx.args end),
          }),
        })),
      })

      local parsed = app:parse({ "worker" })
      local ctx = context_mod.create_context({
        target_node = parsed.target_node,
        route = parsed.route,
      })

      -- Dispatch SIGINT
      local int_res = app:handle_signal("SIGINT", ctx)
      assert.equal(interrupt_called, true)
      assert.equal(terminate_called, false)
      assert.equal(int_res.action, "prompt")
      assert.equal(received_int_event.signal, "interrupt")
      assert.equal(received_int_event.raw_signal, "SIGINT")

      -- Dispatch SIGTERM
      local term_res = app:handle_signal("SIGTERM", ctx)
      assert.equal(terminate_called, true)
      assert.equal(term_res.action, "shutdown")
      assert.equal(term_res.opts.grace_ms, 500)
      assert.equal(received_term_event.signal, "terminate")
      assert.equal(received_term_event.raw_signal, "SIGTERM")
    end)

    it("Section 34: nearest active policy is consulted first (child overrides parent)", function()
      local parent_int_called = false
      local child_int_called = false

      local app = c.create({
        name = "test-signal-hierarchy",
        c.root(c.node({
          c.signals({
            interrupt = function(ctx, evt)
              parent_int_called = true
              return { action = "parent_action" }
            end,
          }),

          task = c.node({
            c.signals({
              interrupt = function(ctx, evt)
                child_int_called = true
                return { action = "child_action" }
              end,
            }),

            c.run(function(ctx) return ctx.args end),
          }),
        })),
      })

      local parsed = app:parse({ "task" })
      local ctx = context_mod.create_context({
        target_node = parsed.target_node,
        route = parsed.route,
      })

      local res = app:handle_signal("SIGINT", ctx)
      assert.equal(child_int_called, true)
      assert.equal(parent_int_called, false)
      assert.equal(res.action, "child_action")
    end)
  end)

end)
