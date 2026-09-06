local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Structured Scope Lifetime & Exactly-Once Release (HOST-INV-06)", function()

  it("guarantees host:close() executes on normal successful completion", function()
    local rec = c.recording_host()
    local app = c.create({
      name = "success-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx) return "ok" end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(rec.is_closed)
  end)

  it("guarantees host:close() executes when application handler raises error", function()
    local rec = c.recording_host()
    local app = c.create({
      name = "error-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          error("Fatal business exception inside handler")
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 1)

    assert.truthy(rec.is_closed, "host:close() executed despite error")
    assert.truthy(rec.result, "host:finish() executed on error")
    assert.equal(rec.result.status, "failed")
    assert.equal(rec.result.exit_code, 1)
  end)

  it("guarantees host:close() executes when nested scopes unwind", function()
    local rec = c.recording_host()
    local unwound_order = {}

    local app = c.create({
      name = "scope-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          return ctx:scope(function(scope)
            scope:defer(function()
              table.insert(unwound_order, "nested_scope_defer")
            end)
            return "nested_done"
          end)
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.truthy(rec.is_closed)
    assert.same(unwound_order, { "nested_scope_defer" })
  end)

end)
