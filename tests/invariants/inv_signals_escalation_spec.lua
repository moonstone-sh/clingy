local h = require("tests.harness")
local c = require("clingy")
local signals = require("clingy.signals")
local context_mod = require("clingy.context")
local events = require("clingy.events")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant: Signal Identity and Escalation Semantics (Section 16-20)", function()

  it("distinguishes INT vs TERM as separate semantic identities", function()
    assert.equal(signals.normalize(2), "interrupt")
    assert.equal(signals.normalize("SIGINT"), "interrupt")
    assert.equal(signals.normalize("INT"), "interrupt")

    assert.equal(signals.normalize(15), "terminate")
    assert.equal(signals.normalize("SIGTERM"), "terminate")
    assert.equal(signals.normalize("TERM"), "terminate")
  end)

  it("escalates to force_shutdown when a second SIGINT is received (Section 19)", function()
    local bus = events.create_bus()
    local ctx = context_mod.create_context({ bus = bus })

    local res1 = signals.dispatch("SIGINT", ctx)
    assert.equal(res1.action, "interrupt")

    local res2 = signals.dispatch("SIGINT", ctx)
    assert.equal(res2.action, "force_shutdown")
    assert.equal(res2.reason, "second_sigint")
  end)

  it("Section 20: SIGTERM supersedes active interactive confirmation and forces shutdown", function()
    local bus = events.create_bus()
    local ctx = context_mod.create_context({ bus = bus })

    -- Simulate active interactive confirmation prompt
    ctx._prompt_active = true

    local res = signals.dispatch("SIGTERM", ctx)
    assert.equal(res.action, "force_shutdown")
    assert.equal(res.reason, "terminate_during_confirmation")
    assert.equal(ctx._prompt_active, false)
  end)

end)
