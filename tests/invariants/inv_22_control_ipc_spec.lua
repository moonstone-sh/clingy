local h = require("tests.harness")
local c = require("clingy")
local process = require("clingy.process")
local events = require("clingy.events")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 22: Control IPC Channel Isolation (Section 41)", function()

  it("isolates control IPC messages from stdout and stderr buffers", function()
    local bus = events.create_bus()
    local ctx = { bus = bus }

    local proc = process.ManagedProcess.new({
      argv = { "echo", "stdout-payload" },
    }, ctx)

    -- Send structured control IPC messages
    proc:send_ipc({ type = "HEARTBEAT", timestamp = 1788600000 })
    proc:send_ipc({ type = "STATUS_QUERY", target = "worker-1" })

    -- Wait for process to execute stdout payload
    local exit_code, stdout, stderr = proc:wait()

    assert.equal(exit_code, 0)
    assert.matches(stdout, "stdout%-payload")

    -- Invariant 22: Control IPC messages must NOT appear in stdout or stderr
    assert.is_nil(stdout:find("HEARTBEAT"))
    assert.is_nil(stdout:find("STATUS_QUERY"))
    assert.is_nil(stderr:find("HEARTBEAT"))

    -- Verify IPC outbox preserved the messages independently
    assert.equal(#proc.ipc_outbox, 2)
    assert.equal(proc.ipc_outbox[1].type, "HEARTBEAT")
    assert.equal(proc.ipc_outbox[2].type, "STATUS_QUERY")
  end)

  it("handles incoming control IPC messages independently of process execution", function()
    local proc = process.ManagedProcess.new({})

    local received = {}
    proc:on_ipc(function(msg)
      table.insert(received, msg)
    end)

    proc:push_ipc({ cmd = "PAUSE" })
    proc:push_ipc({ cmd = "RESUME" })

    assert.equal(#received, 2)
    assert.equal(received[1].cmd, "PAUSE")
    assert.equal(received[2].cmd, "RESUME")

    local polled1 = proc:recv_ipc()
    local polled2 = proc:recv_ipc()
    local polled3 = proc:recv_ipc()

    assert.equal(polled1.cmd, "PAUSE")
    assert.equal(polled2.cmd, "RESUME")
    assert.is_nil(polled3)
  end)

  it("emits process_ipc_send events over the semantic event bus", function()
    local bus = events.create_bus()
    local captured_bus_events = {}

    bus:on("process_ipc_send", function(evt)
      table.insert(captured_bus_events, evt)
    end)

    local proc = process.ManagedProcess.new({
      pid = "proc-test-123",
    }, { bus = bus })

    proc:send_ipc({ op = "RELOAD_CONFIG" })

    assert.equal(#captured_bus_events, 1)
    assert.equal(captured_bus_events[1].process_id, "proc-test-123")
    assert.equal(captured_bus_events[1].message.op, "RELOAD_CONFIG")
  end)

end)
