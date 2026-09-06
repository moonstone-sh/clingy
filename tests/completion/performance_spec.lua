--[[
  tests/completion/performance_spec.lua
  Completion Engine Performance & Latency Benchmark:
  Verifies that completion queries execute in < 50ms (strictly interactive threshold).
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Completion Engine Latency & Performance Benchmark", function()

  -- Build a complex multi-command tree with flags, options, and schemas
  local subcommands = {}
  for i = 1, 30 do
    local cmd_name = "cmd_" .. i
    subcommands[cmd_name] = c.node({
      c.flag("-a", "--all"),
      c.flag("-f", "--force"),
      c.option("-e", "--env", v.picklist({ "dev", "stage", "prod", "test" })),
      c.option("-p", "--port", v.integer()),
      c.complete(c.values("fast", "medium", "slow"), c.arg("speed")),
      c.run(function() end),
    }, { description = "Subcommand number " .. i })
  end

  local app = c.create({
    name = "bench_cli",
    c.root(c.node(subcommands)),
  })

  it("completes root subcommands with latency strictly under 50ms", function()
    local iterations = 100
    local t0 = os.clock()

    for _ = 1, iterations do
      local resp = app:complete({ "bench_cli", "cmd_" })
      assert.equal(#resp.candidates, 30)
    end

    local elapsed_sec = os.clock() - t0
    local avg_ms = (elapsed_sec / iterations) * 1000

    print(string.format("      [Perf Benchmark] Root completion avg latency: %.3f ms across %d runs", avg_ms, iterations))
    assert.truthy(avg_ms < 50, string.format("Average completion latency %.3f ms must be < 50 ms", avg_ms))
  end)

  it("completes deep option values with picklist schema discovery under 50ms", function()
    local iterations = 100
    local t0 = os.clock()

    for _ = 1, iterations do
      local resp = app:complete({ "bench_cli", "cmd_15", "--env", "" })
      assert.equal(#resp.candidates, 4)
    end

    local elapsed_sec = os.clock() - t0
    local avg_ms = (elapsed_sec / iterations) * 1000

    print(string.format("      [Perf Benchmark] Option picklist completion avg latency: %.3f ms across %d runs", avg_ms, iterations))
    assert.truthy(avg_ms < 50, string.format("Average completion latency %.3f ms must be < 50 ms", avg_ms))
  end)

  it("executes full app:run entrypoint with --__clingy-complete under 50ms", function()
    local fake_stdout = { write = function() end }
    local iterations = 100
    local t0 = os.clock()

    for _ = 1, iterations do
      local code = app:run({
        "--__clingy-complete",
        "bash",
        "bench_cli",
        "cmd_7",
        "--env",
        "",
        "--cword=4",
      }, { stdout = fake_stdout })
      assert.equal(code, 0)
    end

    local elapsed_sec = os.clock() - t0
    local avg_ms = (elapsed_sec / iterations) * 1000

    print(string.format("      [Perf Benchmark] Full entrypoint app:run completion avg latency: %.3f ms across %d runs", avg_ms, iterations))
    assert.truthy(avg_ms < 50, string.format("Average entrypoint latency %.3f ms must be < 50 ms", avg_ms))
  end)

end)
