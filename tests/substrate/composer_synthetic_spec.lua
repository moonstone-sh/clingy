local h = require("tests.harness")
local composer_mod = require("clingy.composer")
local events = require("clingy.events")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Substrate: Composer Synthetic Event Stream Testing (Section 44)", function()

  local function emit_synthetic_events(bus)
    local s1 = bus:start_span("compilation")
    bus:emit("log", { level = "info", message = "Building target..." })
    bus:emit("progress", { task = "build", percentage = 10, message = "Parsing files" })
    bus:emit("progress", { task = "build", percentage = 50, message = "Compiling C sources" })
    bus:emit("progress", { task = "build", percentage = 100, message = "Linking binary" })
    bus:emit("milestone", { message = "Build artifact generated" })
    bus:end_span(s1, "ok")
    bus:emit("result", { data = "Done in 0.42s" })
  end

  it("renders plain mode with zero ANSI codes and milestone reduction", function()
    local composer = composer_mod.create_composer({
      mode = "plain",
      capture = true,
    })
    local bus = events.create_bus("test-inv-42")
    composer:attach(bus)
    emit_synthetic_events(bus)

    assert.truthy(#composer.captured_lines > 0)
    for _, line in ipairs(composer.captured_lines) do
      -- Invariant 21: Zero ANSI codes
      assert.falsy(line:find("\27%["), "Plain mode must not contain ANSI escape sequences: " .. line)
    end

    -- Verify progress was reduced to milestone / start instead of 10%, 50%, 100% spam
    local combined = table.concat(composer.captured_lines, "\n")
    assert.matches(combined, "Starting: compilation")
    assert.matches(combined, "=> Build artifact generated")
    assert.matches(combined, "Finished: compilation")
    assert.matches(combined, "Done in 0.42s")
  end)

  it("renders json mode as valid NDJSON envelopes with protocol version", function()
    local composer = composer_mod.create_composer({
      mode = "json",
      capture = true,
    })
    local bus = events.create_bus("test-inv-42")
    composer:attach(bus)
    emit_synthetic_events(bus)

    assert.truthy(#composer.captured_lines > 0)
    for _, line in ipairs(composer.captured_lines) do
      assert.matches(line, '"protocol":"clingy.events.v1"')
      assert.matches(line, '"sequence":')
      assert.matches(line, '"type":')
    end
  end)

  it("renders quiet mode suppressing progress, spans, and standard logs", function()
    local composer = composer_mod.create_composer({
      mode = "quiet",
      capture = true,
    })
    local bus = events.create_bus("test-inv-42")
    composer:attach(bus)
    emit_synthetic_events(bus)

    local combined = table.concat(composer.captured_lines, "\n")
    assert.falsy(combined:find("Starting: compilation"))
    assert.falsy(combined:find("Parsing files"))
    assert.matches(combined, "Done in 0.42s")
  end)

end)
