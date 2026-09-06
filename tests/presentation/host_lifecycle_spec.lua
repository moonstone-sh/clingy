local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Presentation Host Lifecycle & Boundaries (HOST-INV-01, 05, 07)", function()

  it("executes full lifecycle sequence: start -> handle_event -> finish -> close", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "test-app",
      version = "1.0.0",
      presentation = rec,
      c.root(c.node({
        build = c.node({
          c.run(function(ctx)
            ctx:log("info", "Building artifact")
            ctx:progress("build", 100, "Done")
            return { status = "built" }
          end),
        }),
      })),
    })

    local exit_code = app:run({ "build" })
    assert.equal(exit_code, 0)

    -- Assert lifecycle methods were called in exact order
    local call_methods = {}
    for _, call in ipairs(rec.calls) do
      if call.method ~= "handle_event" then
        table.insert(call_methods, call.method)
      end
    end

    assert.equal(call_methods[1], "start", "start called first")
    assert.equal(rec.invocation.app_name, "test-app")
    assert.same(rec.invocation.argv, { "build" })

    -- Verify finish called before close
    assert.truthy(rec.result, "finish result recorded")
    assert.equal(rec.result.status, "ok")
    assert.equal(rec.result.exit_code, 0)

    assert.truthy(rec.is_closed, "host closed")
    assert.equal(call_methods[#call_methods], "close", "close called last")
  end)

  it("calls host:start BEFORE argument parsing, ensuring parse failures reach started host", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "parse-app",
      version = "1.0.0",
      presentation = rec,
      c.root(c.node({
        deploy = c.node({
          c.arg("env", v.picklist({ "dev", "prod" })),
          c.run(function(ctx) end),
        }),
      })),
    })

    -- Provide invalid command to trigger parse error
    local exit_code = app:run({ "invalid-command" })
    assert.equal(exit_code, 1)

    -- Assert start was called before diagnostic event
    assert.truthy(rec.invocation, "host:start called even on parse error")
    assert.equal(rec.calls[1].method, "start")

    -- Assert finish and close were called on parse error
    assert.truthy(rec.result)
    assert.equal(rec.result.status, "failed")
    assert.equal(rec.result.exit_code, 1)
    assert.truthy(rec.is_closed, "host closed on parse error")

    -- Verify diagnostic event was received
    local diag = nil
    for _, evt in ipairs(rec.events) do
      if evt.type == "diagnostic" then diag = evt break end
    end
    assert.truthy(diag, "received diagnostic event for parse error")
  end)

  it("guarantees single host ownership per invocation", function()
    local host1 = c.recording_host()
    local host2 = c.recording_host()

    local app = c.create({
      name = "multi-host-test",
      presentation = host1,
      c.root(c.node({
        c.run(function(ctx)
          ctx:log("info", "Hello from handler")
        end),
      })),
    })

    -- Override host per invocation
    local exit_code = app:run({}, { presentation = host2 })
    assert.equal(exit_code, 0)

    -- Host2 was active, Host1 was never invoked
    assert.equal(#host2.calls > 0, true)
    assert.equal(#host1.calls, 0)
    assert.truthy(host2.is_closed)
    assert.falsy(host1.is_closed)
  end)

  it("treats host:start failure as a fatal presentation initialization error", function()
    local failing_host = c.failing_host({ fail_on = { start = "Failed to allocate terminal screen buffer" } })
    local handler_called = false

    local app = c.create({
      name = "fatal-start-app",
      presentation = failing_host,
      c.root(c.node({
        c.run(function(ctx)
          handler_called = true
          return "done"
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 1, "app:run fails when host:start fails")
    assert.falsy(handler_called, "application handler was NOT called")
  end)

  it("enforces explicit host lifecycle state machine and rejects invalid transitions", function()
    local host_mod = require("clingy.presentation.host")
    local host = host_mod.PresentationHost.new()

    assert.equal(host:state(), "created")

    -- Reject resume when active or created
    assert.has_error(function()
      host:resume()
    end, "not suspended")

    -- Reject suspend before start
    assert.has_error(function()
      host:suspend()
    end, "in state created")

    -- Start host
    host:start({ invocation_id = "test-1", app_name = "test", argv = {} })
    assert.equal(host:state(), "started")

    -- Handle event transitions to active
    host:handle_event({ protocol = "clingy.events.v1", type = "log", message = "hi" })
    assert.equal(host:state(), "active")

    -- Reject resume while already active
    assert.has_error(function()
      host:resume()
    end, "not suspended")

    -- Suspend host
    host:suspend("test_suspend")
    assert.equal(host:state(), "suspended")

    -- Reject double suspend
    assert.has_error(function()
      host:suspend()
    end, "already suspended")

    -- Resume host
    host:resume()
    assert.equal(host:state(), "active")

    -- Finish host
    host:finish({ status = "ok", exit_code = 0 })
    assert.equal(host:state(), "finished")

    -- Close host
    host:close()
    assert.equal(host:state(), "closed")

    -- Double close is safe / idempotent
    assert.no_error(function()
      host:close()
    end)
    assert.equal(host:state(), "closed")

    -- Reject handle_event after close
    assert.has_error(function()
      host:handle_event({ type = "log" })
    end, "already closed")
  end)

end)
