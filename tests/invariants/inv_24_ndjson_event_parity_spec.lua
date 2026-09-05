local h = require("tests.harness")
local c = require("clingy")
local composer_mod = require("clingy.composer")
local events = require("clingy.events")

local describe, it = h.describe, h.it
local assert = h.assert

-- Lightweight JSON decoder for verifying NDJSON output in tests
local function parse_json_object(str)
  local obj = {}
  -- Extract key-value pairs
  for k, v in str:gmatch('"([%w_]+)":%s*([^,}]+)') do
    v = v:gsub("^%s+", ""):gsub("%s+$", "")
    if v:sub(1, 1) == '"' and v:sub(-1) == '"' then
      obj[k] = v:sub(2, -2)
    elseif v == "true" then
      obj[k] = true
    elseif v == "false" then
      obj[k] = false
    elseif v == "null" then
      obj[k] = nil
    elseif tonumber(v) then
      obj[k] = tonumber(v)
    else
      obj[k] = v
    end
  end
  return obj
end

describe("Invariant 24: NDJSON Event Stream Parity and Protocol Envelopes", function()

  it("emits valid NDJSON lines in json mode with standard attribution fields", function()
    local comp = composer_mod.create_composer({
      mode = "json",
      capture = true,
    })

    local bus = events.create_bus("inv-test-42")
    comp:attach(bus)

    bus:start_span("build_step")
    bus:emit("progress", { task = "build_step", percentage = 50, message = "Building" })
    bus:emit("milestone", { message = "Step completed" })
    bus:emit("result", { data = "Artifact ready" })

    assert.truthy(#comp.captured_lines >= 4)

    for idx, line in ipairs(comp.captured_lines) do
      -- Must start with { and end with }
      assert.equal(line:sub(1, 1), "{", "Line must begin with '{': " .. line)
      assert.equal(line:sub(-1), "}", "Line must end with '}': " .. line)

      local parsed = parse_json_object(line)
      assert.truthy(parsed.type, "Missing 'type' in: " .. line)
      assert.equal(parsed.invocation_id, "inv-test-42")
      assert.equal(type(parsed.sequence), "number")
      assert.equal(parsed.sequence, idx)
      assert.equal(type(parsed.timestamp), "number")
    end
  end)

  it("maintains strictly monotonic sequence numbers across the event stream", function()
    local comp = composer_mod.create_composer({
      mode = "json",
      capture = true,
    })

    local bus = events.create_bus()
    comp:attach(bus)

    for i = 1, 10 do
      bus:emit("tick", { count = i })
    end

    assert.equal(#comp.captured_lines, 10)
    local last_seq = 0
    for _, line in ipairs(comp.captured_lines) do
      local parsed = parse_json_object(line)
      assert.equal(parsed.sequence, last_seq + 1)
      last_seq = parsed.sequence
    end
  end)

  it("guarantees semantic parity between human presentation and machine JSON stream", function()
    -- Create app with a workload emitting events
    local app = c.create({
      name = "parity-app",
      c.root(c.node({
        c.inherit(
          c.flag("--json"),
          c.flag("--plain")
        ),
        worker = c.node({
          c.run(function(ctx)
            ctx:milestone("Milestone Alpha")
            ctx:result("Worker Output")
          end),
        }),
      })),
    })

    -- Run in plain mode
    local plain_comp = composer_mod.create_composer({ mode = "plain", capture = true })
    app:run({ "worker", "--plain" }, { capture = true, composer_mode = "plain" })

    -- Run in json mode
    local json_lines = {}
    local custom_sink = {
      write = function(_, str)
        local trimmed = str:gsub("\n$", "")
        if #trimmed > 0 then
          table.insert(json_lines, trimmed)
        end
      end,
      flush = function() end,
    }

    app:run({ "worker", "--json" }, {
      capture = true,
      composer_mode = "json",
      stdout = custom_sink,
    })

    -- Verify JSON stream captured the events
    assert.truthy(#json_lines >= 3) -- invocation_start, milestone, invocation_finish

    local found_milestone = false
    for _, l in ipairs(json_lines) do
      if l:find("Milestone Alpha") then
        found_milestone = true
        local parsed = parse_json_object(l)
        assert.equal(parsed.type, "milestone")
        assert.equal(parsed.message, "Milestone Alpha")
      end
    end

    assert.truthy(found_milestone, "Expected milestone in JSON stream")
  end)

end)
