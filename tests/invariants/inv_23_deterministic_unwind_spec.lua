local h = require("tests.harness")
local c = require("clingy")
local scope_mod = require("clingy.scope")
local context_mod = require("clingy.context")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 23: Deterministic Scope Unwind and LIFO Cleanup", function()

  it("executes deferred callbacks in strict Last-In-First-Out (LIFO) order on success", function()
    local execution_order = {}

    local ctx = context_mod.create_context({})
    local result = ctx:scope(function(scope)
      scope:defer(function()
        table.insert(execution_order, "first_registered")
      end)

      scope:defer(function()
        table.insert(execution_order, "second_registered")
      end)

      scope:defer(function()
        table.insert(execution_order, "third_registered")
      end)

      return "scope_done"
    end)

    assert.equal(result, "scope_done")
    -- Must execute in reverse order: 3 -> 2 -> 1
    assert.same(execution_order, {
      "third_registered",
      "second_registered",
      "first_registered",
    })
  end)

  it("executes deferred callbacks in LIFO order when an error occurs", function()
    local execution_order = {}
    local captured_reason = nil

    local ctx = context_mod.create_context({})

    local ok, err = pcall(function()
      ctx:scope(function(scope)
        scope:defer(function(reason)
          captured_reason = reason
          table.insert(execution_order, "first")
        end)

        scope:defer(function()
          table.insert(execution_order, "second")
        end)

        error("Something failed inside scope")
      end)
    end)

    assert.falsy(ok)
    assert.matches(tostring(err), "Something failed inside scope")

    -- Callbacks still executed in LIFO order despite error
    assert.same(execution_order, { "second", "first" })
    assert.equal(captured_reason, "error")
  end)

  it("unwinds nested child scopes before parent callbacks", function()
    local order = {}

    local ctx = context_mod.create_context({})
    ctx:scope(function(parent)
      parent:defer(function()
        table.insert(order, "parent_defer")
      end)

      parent:scope(function(child)
        child:defer(function()
          table.insert(order, "child_defer_1")
        end)

        child:defer(function()
          table.insert(order, "child_defer_2")
        end)
      end)
    end)

    assert.same(order, {
      "child_defer_2",
      "child_defer_1",
      "parent_defer",
    })
  end)

  it("aggregates cleanup errors without preventing remaining callbacks from executing", function()
    local executed = {}

    local scope = scope_mod.create_scope()

    scope:defer(function()
      table.insert(executed, "final_defer")
    end)

    scope:defer(function()
      table.insert(executed, "faulty_defer")
      error("Defective cleanup callback")
    end)

    scope:defer(function()
      table.insert(executed, "initial_defer")
    end)

    -- Unwind with reason "error"
    scope:unwind("error")

    -- Both initial_defer and final_defer must execute despite faulty_defer error
    assert.same(executed, {
      "initial_defer",
      "faulty_defer",
      "final_defer",
    })
  end)

  it("supports deterministic unwind on interrupt and termination reasons", function()
    local reasons = {}

    local s1 = scope_mod.create_scope()
    s1:defer(function(reason)
      table.insert(reasons, reason)
    end)
    s1:unwind("interrupt")

    local s2 = scope_mod.create_scope()
    s2:defer(function(reason)
      table.insert(reasons, reason)
    end)
    s2:unwind("termination")

    assert.same(reasons, { "interrupt", "termination" })
  end)

end)
