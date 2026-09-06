local h = require("tests.harness")
local c = require("clingy")
local prompt_mod = require("clingy.presentation.prompt")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Presentation Host Prompt Protocol (HOST-INV-14)", function()

  it("delegates ctx:confirm to host:prompt with confirm request structure", function()
    local rec = c.recording_host({ prompt_responses = { true } })

    local app = c.create({
      name = "confirm-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          local res = ctx:confirm("Apply database migrations?", { default = false, timeout_ms = 5000 })
          return { confirmed = res }
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.equal(#rec.prompts, 1)

    local prompt_req = rec.prompts[1]
    assert.equal(prompt_req.type, "confirm")
    assert.equal(prompt_req.prompt, "Apply database migrations?")
    assert.equal(prompt_req.default, false)
    assert.equal(prompt_req.timeout_ms, 5000)
  end)

  it("delegates ctx:prompt to host:prompt for arbitrary prompt requests", function()
    local rec = c.recording_host({ prompt_responses = { "prod-cluster-01" } })

    local app = c.create({
      name = "custom-prompt-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          local target = ctx:prompt({
            type = "text",
            prompt = "Enter target cluster",
            default = "local-k8s",
          })
          return { target = target }
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.equal(#rec.prompts, 1)
    assert.equal(rec.prompts[1].type, "text")
    assert.equal(rec.prompts[1].prompt, "Enter target cluster")
    assert.equal(rec.prompts[1].default, "local-k8s")
  end)

  it("falls back cleanly to default or false in non-interactive confirm prompts", function()
    -- NullHost uses prompt_mod.fallback
    local null_h = c.null_host()

    local app = c.create({
      name = "fallback-confirm-app",
      presentation = null_h,
      c.root(c.node({
        c.run(function(ctx)
          local c1 = ctx:confirm("Delete everything?") -- no default -> false
          local c2 = ctx:confirm("Keep backup?", { default = true }) -- default true -> true
          local c3 = ctx:confirm("Enable telemetry?", { default = false }) -- default false -> false
          assert.equal(c1, false)
          assert.equal(c2, true)
          assert.equal(c3, false)
          return { c1 = c1, c2 = c2, c3 = c3 }
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
  end)

  it("falls back to default in non-interactive text prompts, or raises clean error without default", function()
    -- NullHost with default
    local null_h = c.null_host()
    local app = c.create({
      name = "fallback-text-app",
      presentation = null_h,
      c.root(c.node({
        c.run(function(ctx)
          local text_val = ctx:prompt({ type = "text", prompt = "Username", default = "guest" })
          assert.equal(text_val, "guest")
        end),
      })),
    })
    local exit_code = app:run({})
    assert.equal(exit_code, 0)

    -- NullHost without default on text prompt raises descriptive error
    local app_error = c.create({
      name = "fallback-text-error-app",
      presentation = c.null_host(),
      c.root(c.node({
        c.run(function(ctx)
          ctx:prompt({ type = "text", prompt = "Password without default" })
        end),
      })),
    })
    local exit_code_err = app_error:run({})
    assert.equal(exit_code_err, 1)
  end)

  it("supports queue of sequential prompt responses in RecordingHost", function()
    local rec = c.recording_host({
      prompt_responses = { true, "staging", false }
    })

    local app = c.create({
      name = "multi-prompt-app",
      presentation = rec,
      c.root(c.node({
        c.run(function(ctx)
          local p1 = ctx:confirm("Step 1?")
          local p2 = ctx:prompt({ type = "text", prompt = "Target env?" })
          local p3 = ctx:confirm("Dry run?")
          return { p1 = p1, p2 = p2, p3 = p3 }
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 0)
    assert.equal(#rec.prompts, 3)
  end)

  it("propagates structured prompt failure when host:prompt throws an error", function()
    local failing_host = c.failing_host({ fail_on = { prompt = "TTY device input stream corrupted" } })

    local app = c.create({
      name = "fail-prompt-app",
      presentation = failing_host,
      c.root(c.node({
        c.run(function(ctx)
          ctx:confirm("Deploy now?")
          return "unreachable"
        end),
      })),
    })

    local exit_code = app:run({})
    assert.equal(exit_code, 1, "app fails when prompt throws fatal presentation error")
  end)

end)
