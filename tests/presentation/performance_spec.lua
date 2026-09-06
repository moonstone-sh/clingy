local h = require("tests.harness")
local c = require("clingy")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Presentation Host Performance & Latency Benchmarks", function()

  it("measures event dispatch latency across 1,000 events through Host boundary", function()
    local rec = c.recording_host()

    local app = c.create({
      name = "perf-events-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          for i = 1, 1000 do
            ctx:log("info", "Benchmark log message " .. tostring(i))
          end
          return { ok = true }
        end),
      })),
    })

    local start_time = os.clock()
    local exit_code = app:run({})
    local duration_ms = (os.clock() - start_time) * 1000

    assert.equal(exit_code, 0)
    local log_events = 0
    for _, evt in ipairs(rec.events) do
      if evt.type == "log" then log_events = log_events + 1 end
    end
    assert.equal(log_events, 1000)

    local avg_per_event_us = (duration_ms / 1000) * 1000
    print(string.format("      [Perf Benchmark] Host boundary 1,000 events: %.2f ms total (%.2f µs / event)", duration_ms, avg_per_event_us))
    -- Host boundary should be well under 100ms for 1,000 events in Lua
    assert.truthy(duration_ms < 100, "1,000 event dispatch takes < 100ms")
  end)

  it("compares invocation latency of NullHost vs RecordingHost vs ComposerHost", function()
    local iterations = 100

    -- 1. NullHost
    local t0 = os.clock()
    for _ = 1, iterations do
      local null_h = c.null_host()
      local app = c.create({
        name = "bench-null",
        presentation = null_h,
        c.root(c.node({
          c.run(function(ctx) ctx:log("info", "hi") end)
        }))
      })
      app:run({})
    end
    local null_duration_ms = (os.clock() - t0) * 1000 / iterations

    -- 2. RecordingHost
    local t1 = os.clock()
    for _ = 1, iterations do
      local rec_h = c.recording_host()
      local app = c.create({
        name = "bench-rec",
        presentation = rec_h,
        c.root(c.node({
          c.run(function(ctx) ctx:log("info", "hi") end)
        }))
      })
      app:run({})
    end
    local rec_duration_ms = (os.clock() - t1) * 1000 / iterations

    -- 3. ComposerHost (plain capture)
    local t2 = os.clock()
    for _ = 1, iterations do
      local comp_h = c.composer({ mode = "plain", capture = true })
      local app = c.create({
        name = "bench-comp",
        presentation = comp_h,
        c.root(c.node({
          c.run(function(ctx) ctx:log("info", "hi") end)
        }))
      })
      app:run({})
    end
    local comp_duration_ms = (os.clock() - t2) * 1000 / iterations

    print(string.format("      [Perf Benchmark] Avg Invocation Latency (N=%d):", iterations))
    print(string.format("        - NullHost:      %.3f ms", null_duration_ms))
    print(string.format("        - RecordingHost: %.3f ms", rec_duration_ms))
    print(string.format("        - ComposerHost:  %.3f ms", comp_duration_ms))

    -- Full create+run cycle per invocation must be comfortably under 5ms
    assert.truthy(null_duration_ms < 5.0)
    assert.truthy(rec_duration_ms < 5.0)
    assert.truthy(comp_duration_ms < 5.0)
  end)

end)
