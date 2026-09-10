local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Canonical Event Ingestion (HOST-INV-04)", function()

  it("delivers full lifecycle of semantic events conforming to clingy.events.v1", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "event-app",
      version = "2.0.0",
      presentation = rec,
      root = c.node({
        c.run(function(ctx)
          ctx:span("phase-1", function()
            ctx:log("info", "Processing payload", { key = "val" })
            ctx:progress("fetch", 50, "Downloading")
            ctx:milestone("Payload fetched")
          end)
          ctx:result({ count = 42 })
        end),
      }),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    local event_types = {}
    for _, evt in ipairs(rec.events) do
      table.insert(event_types, evt.type)
      assert.equal(evt.protocol, "clingy.events.v1")
      assert.truthy(type(evt.sequence) == "number")
      assert.truthy(type(evt.timestamp) == "number")
      assert.truthy(type(evt.invocation_id) == "string")
    end

    assert.truthy(h.contains(event_types, "invocation_start"))
    assert.truthy(h.contains(event_types, "span_start"))
    assert.truthy(h.contains(event_types, "log"))
    assert.truthy(h.contains(event_types, "progress"))
    assert.truthy(h.contains(event_types, "milestone"))
    assert.truthy(h.contains(event_types, "span_end"))
    assert.truthy(h.contains(event_types, "result"))
    assert.truthy(h.contains(event_types, "invocation_finish"))
  end)

end)
