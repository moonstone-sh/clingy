local h = require("tests.harness")
local c = require("clingy")
local composer_mod = require("clingy.composer")
local events = require("clingy.events")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant 20 & 21: Composer Ownership and Plain-Mode Semantic Reduction", function()

  describe("Invariant 20: Composer Ownership of Terminal Display (Section 37)", function()
    it("routes semantic events from bus through the single Composer owner", function()
      local comp = composer_mod.create_composer({
        mode = "plain",
        capture = true,
      })

      local bus = events.create_bus()
      comp:attach(bus)

      bus:emit("milestone", { message = "Database connected" })
      bus:emit("log", { level = "info", message = "Cache warmed" })

      assert.equal(#comp.captured_lines, 2)
      assert.matches(comp.captured_lines[1], "Database connected")
      assert.matches(comp.captured_lines[2], "Cache warmed")
    end)
  end)

  describe("Invariant 21: Plain Mode Semantic Reduction (Section 39)", function()
    it("emits ZERO ANSI escape sequences in plain mode", function()
      local comp = composer_mod.create_composer({
        mode = "plain",
        capture = true,
      })

      local bus = events.create_bus()
      comp:attach(bus)

      bus:start_span("build_bundle")
      bus:emit("progress", { task = "build_bundle", percentage = 10, message = "Packaging" })
      bus:emit("progress", { task = "build_bundle", percentage = 50, message = "Packaging" })
      bus:emit("progress", { task = "build_bundle", percentage = 100, message = "Packaging" })
      bus:end_span("span-1", "ok")
      bus:emit("milestone", { message = "Build complete" })
      bus:emit("result", { data = "Done" })

      for _, line in ipairs(comp.captured_lines) do
        -- No ANSI escape codes (\27 or \x1b)
        assert.is_nil(line:find("\27"), "Plain mode line must not contain ANSI escape codes: " .. line)
      end
    end)

    it("reduces high-frequency progress ticks to semantic milestones in plain mode", function()
      local comp = composer_mod.create_composer({
        mode = "plain",
        capture = true,
      })

      local bus = events.create_bus()
      comp:attach(bus)

      -- Emit multiple intermediate percentage updates for the same task
      bus:emit("progress", { task = "download", percentage = 10, message = "Downloading asset" })
      bus:emit("progress", { task = "download", percentage = 20, message = "Downloading asset" })
      bus:emit("progress", { task = "download", percentage = 30, message = "Downloading asset" })
      bus:emit("progress", { task = "download", percentage = 90, message = "Downloading asset" })
      bus:emit("progress", { task = "download", percentage = 100, message = "Asset downloaded" })

      -- Section 39: Plain mode does NOT print 10%, 20%, 30% individually
      -- It reduces progress to start and completion
      local tick_count = 0
      for _, line in ipairs(comp.captured_lines) do
        if line:find("Downloading asset") or line:find("Asset downloaded") then
          tick_count = tick_count + 1
        end
      end

      -- Must be significantly fewer than the 5 raw progress events emitted
      assert.truthy(tick_count <= 2, "Expected plain mode to reduce progress ticks, got " .. tick_count)
    end)
  end)

  describe("Presentation Mode: quiet (Section 38)", function()
    it("suppresses progress, spans, and standard logs, but preserves errors and results", function()
      local comp = composer_mod.create_composer({
        mode = "quiet",
        capture = true,
      })

      local bus = events.create_bus()
      comp:attach(bus)

      bus:start_span("init")
      bus:emit("progress", { task = "init", percentage = 50, message = "Initializing" })
      bus:emit("milestone", { message = "Step 1 done" })
      bus:emit("log", { level = "info", message = "Normal info log" })
      bus:emit("log", { level = "error", message = "Critical failure" })
      bus:emit("result", { data = "Final result data" })

      -- Only error log and result data should be emitted
      assert.equal(#comp.captured_lines, 2)
      assert.equal(comp.captured_lines[1], "Critical failure")
      assert.equal(comp.captured_lines[2], "Final result data")
    end)
  end)

  describe("Presentation Mode: auto (Section 38)", function()
    it("selects fancy mode on interactive TTY", function()
      local comp = composer_mod.create_composer({
        mode = "auto",
        is_tty = true,
        capture = true,
      })
      assert.equal(comp.mode, "fancy")
    end)

    it("selects plain mode on non-TTY / CI", function()
      local comp = composer_mod.create_composer({
        mode = "auto",
        is_tty = false,
        capture = true,
      })
      assert.equal(comp.mode, "plain")
    end)
  end)

end)
