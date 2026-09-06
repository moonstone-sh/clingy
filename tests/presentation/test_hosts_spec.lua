local h = require("tests.harness")
local c = require("clingy")
local host_mod = require("clingy.presentation.host")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Built-in Test Hosts: NullHost, RecordingHost, FailingHost (HOST-INV-08)", function()

  describe("NullHost", function()
    it("conforms to PresentationHost interface and safely accepts all lifecycle calls", function()
      local null_h = c.null_host()
      assert.truthy(host_mod.is_host(null_h))

      -- Calling methods should not raise
      null_h:start({ invocation_id = "test-123", app_name = "null-app", argv = {} })
      null_h:handle_event({ protocol = "clingy.events.v1", type = "log", message = "Hello" })
      null_h:flush()
      null_h:suspend("interactive_child")
      null_h:resume()
      local conf = null_h:prompt({ type = "confirm", default = true })
      assert.equal(conf, true)
      null_h:finish({ status = "ok", exit_code = 0 })
      null_h:close()
    end)

    it("runs an end-to-end app silently with zero output or side-effects", function()
      local null_h = c.null_host()
      local app = c.create({
        name = "null-test-app",
        presentation = null_h,
        c.root(c.node({
          c.run(function(ctx)
            ctx:log("info", "Silent message")
            ctx:progress("step", 50)
            ctx:result("Hidden payload")
            return { ok = true }
          end),
        })),
      })

      local exit_code = app:run({})
      assert.equal(exit_code, 0)
    end)
  end)

  describe("RecordingHost", function()
    it("records full event log, method call sequence, and prompt interactions", function()
      local rec = c.recording_host()
      assert.truthy(host_mod.is_host(rec))

      local app = c.create({
        name = "recording-test-app",
        presentation = rec,
        c.root(c.node({
          c.run(function(ctx)
            ctx:log("warn", "Warning 1")
            ctx:log("error", "Error 1")
            return { processed = true }
          end),
        })),
      })

      local exit_code = app:run({})
      assert.equal(exit_code, 0)

      local logs = {}
      for _, evt in ipairs(rec.events) do
        if evt.type == "log" then table.insert(logs, evt) end
      end
      assert.equal(#logs, 2)
      assert.equal(logs[1].level, "warn")
      assert.equal(logs[2].level, "error")

      assert.truthy(rec.is_closed)
      assert.truthy(rec.result)
      assert.equal(rec.result.status, "ok")
    end)
  end)

  describe("FailingHost", function()
    it("conforms to PresentationHost interface and injects faults on specified methods", function()
      local failing_start = c.failing_host({ fail_on = { start = "Failed to initialize host" } })
      local ok_start, err_start = pcall(function()
        failing_start:start({ invocation_id = "test", app_name = "app", argv = {} })
      end)
      assert.falsy(ok_start)
      assert.truthy(err_start:find("Failed to initialize host"))

      local failing_event = c.failing_host({ fail_on = { handle_event = "Event pipe broken" } })
      local ok_evt, err_evt = pcall(function()
        failing_event:handle_event({ type = "log" })
      end)
      assert.falsy(ok_evt)
      assert.truthy(err_evt:find("Event pipe broken"))
    end)
  end)

end)
