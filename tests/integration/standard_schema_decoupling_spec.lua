--[[
  tests/integration/standard_schema_decoupling_spec.lua
  Verifies Clingy's decoupled Standard Schema v1 architecture.
  Guarantees zero hard dependency on Valua or any single validation vendor.
]]

local h = require("tests.harness")
local c = require("clingy")
local fixture_schema = require("tests.fixtures.fixture_schema")

h.describe("Standard Schema v1 Decoupled Architecture & Schema Adapters", function()

  h.it("1. registered custom schema adapter via c.schema_adapter verifies integer coercion and validation", function()
    -- Register custom fixture adapter
    c.schema_adapter({
      name = "fixture",
      match = function(s)
        return type(s) == "table" and s["~standard"] and s["~standard"].vendor == "fixture-validator"
      end,
      lexical = function(schema, token)
        if schema.kind == "integer" or (schema["~standard"] and schema["~standard"].kind == "integer") then
          local n = tonumber(token)
          if n and math.tointeger then
            return math.tointeger(n) or n
          end
          return n or token
        end
        return token
      end,
    })

    local count_arg = c.arg("count", fixture_schema.integer({ min = 5 }))
    local captured = nil

    local app = c.create({
      name = "test-custom-adapter",
      c.root(c.node({
        count_arg,
        c.run(function(ctx)
          captured = ctx.args.count
        end),
      })),
    })

    -- Valid integer above min: token "42" is coerced to number 42 by fixture adapter
    local code = app:run({ "42" }, { capture = true })
    h.assert.equal(code, 0, "execution succeeded")
    h.assert.equal(type(captured), "number", "coerced to integer number by custom adapter")
    h.assert.equal(captured, 42, "exact value 42 delivered")

    -- Min validation rejection: 3 < 5
    h.assert.has_error(function()
      app:parse({ "3" })
    end, "Validation failed", "rejects integer below min = 5")

    -- Non-numeric rejection: "abc"
    h.assert.has_error(function()
      app:parse({ "abc" })
    end, "Validation failed", "rejects non-numeric string")
  end)

  h.it("2. unadapted schema (no adapter registered) passes raw argv string directly to ~standard.validate without guessing .kind or .type", function()
    local received_val = nil
    local received_type = nil

    -- Unadapted schema with .kind and .type explicitly set to "integer" and "number",
    -- but vendor is "unadapted-vendor" with NO registered adapter in Clingy.
    local unadapted_schema = {
      kind = "integer",
      type = "number",
      ["~standard"] = {
        version = 1,
        vendor = "unadapted-vendor",
        kind = "integer",
        validate = function(val)
          received_val = val
          received_type = type(val)
          if type(val) ~= "string" then
            return { issues = { { message = "Expected raw string token without coercion" } } }
          end
          return { value = "processed:" .. val }
        end,
      },
    }

    local captured_result = nil
    local app = c.create({
      name = "test-unadapted",
      c.root(c.node({
        c.arg("raw_token", unadapted_schema),
        c.run(function(ctx)
          captured_result = ctx.args.raw_token
        end),
      })),
    })

    local code = app:run({ "12345" }, { capture = true })
    h.assert.equal(code, 0, "execution succeeded")
    -- Critical assertion: Clingy did NOT guess .kind or .type to coerce to number!
    h.assert.equal(received_type, "string", "raw argv string was passed directly to validate()")
    h.assert.equal(received_val, "12345", "received exact raw string '12345'")
    h.assert.equal(captured_result, "processed:12345", "delivered transformed output value")
  end)

  h.it("3. mixed validators in single CLI router (Valua with built-in adapter + fixture with custom adapter + unadapted schema)", function()
    local v = require("valua")

    -- Register fixture adapter
    c.schema_adapter({
      name = "fixture",
      match = function(s)
        return type(s) == "table" and s["~standard"] and s["~standard"].vendor == "fixture-validator"
      end,
      lexical = function(schema, token)
        if schema.kind == "integer" or (schema["~standard"] and schema["~standard"].kind == "integer") then
          local n = tonumber(token)
          if n and math.tointeger then return math.tointeger(n) or n end
          return n or token
        end
        return token
      end,
    })

    -- Unadapted schema (no adapter registered, has .kind = "integer")
    local unadapted = {
      kind = "integer",
      ["~standard"] = {
        version = 1,
        vendor = "foreign-unadapted",
        validate = function(val)
          if type(val) ~= "string" then
            return { issues = { { message = "Unadapted schema expected raw string" } } }
          end
          return { value = "raw[" .. val .. "]" }
        end,
      },
    }

    local captured = {}

    local app = c.create({
      name = "test-mixed-validators",
      c.root(c.node({
        -- Route A: Valua with built-in adapter
        valua_cmd = c.node({
          c.option("-p", "--port", v.integer()),
          c.run(function(ctx)
            captured = { source = "valua", port = ctx.args.port }
          end),
        }),

        -- Route B: Fixture with custom registered adapter
        fixture_cmd = c.node({
          c.option("-c", "--count", fixture_schema.integer({ min = 1, max = 100 })),
          c.run(function(ctx)
            captured = { source = "fixture", count = ctx.args.count }
          end),
        }),

        -- Route C: Unadapted schema (receives raw string)
        unadapted_cmd = c.node({
          c.arg("target", unadapted),
          c.run(function(ctx)
            captured = { source = "unadapted", target = ctx.args.target }
          end),
        }),
      })),
    })

    -- Execute Valua command
    local code_v = app:run({ "valua_cmd", "-p", "8080" }, { capture = true })
    h.assert.equal(code_v, 0)
    h.assert.equal(captured.source, "valua")
    h.assert.equal(type(captured.port), "number")
    h.assert.equal(captured.port, 8080)

    -- Execute Fixture command
    local code_f = app:run({ "fixture_cmd", "-c", "42" }, { capture = true })
    h.assert.equal(code_f, 0)
    h.assert.equal(captured.source, "fixture")
    h.assert.equal(type(captured.count), "number")
    h.assert.equal(captured.count, 42)

    -- Execute Unadapted command
    local code_u = app:run({ "unadapted_cmd", "9999" }, { capture = true })
    h.assert.equal(code_u, 0)
    h.assert.equal(captured.source, "unadapted")
    h.assert.equal(captured.target, "raw[9999]")
  end)

  h.it("4. complete Valua absence test: wipe and block valua from package.loaded and package.preload", function()
    local orig_loaded = package.loaded["valua"]
    local orig_preload = package.preload["valua"]

    package.loaded["valua"] = nil
    package.preload["valua"] = function()
      error("VALUA IS STRICTLY BLOCKED: Clingy must execute with zero Valua dependency")
    end

    local test_ok, test_err = pcall(function()
      local require_ok = pcall(require, "valua")
      h.assert.equal(require_ok, false, "valua require is strictly blocked")

      -- Register custom fixture adapter
      c.schema_adapter({
        name = "fixture",
        match = function(s)
          return type(s) == "table" and s["~standard"] and s["~standard"].vendor == "fixture-validator"
        end,
        lexical = function(schema, token)
          if schema.kind == "integer" or (schema["~standard"] and schema["~standard"].kind == "integer") then
            local n = tonumber(token)
            if n and math.tointeger then return math.tointeger(n) or n end
            return n or token
          end
          return token
        end,
      })

      local captured = nil

      local port_opt = c.option("-p", "--port", fixture_schema.integer({ min = 1000 }))
      local mode_opt = c.option("-m", "--mode", fixture_schema.string())

      local app = c.create({
        name = "pure-decoupled-cli",
        c.root(c.node({
          c.inherit(c.flag("-v", "--verbose")),
          deploy = c.node({
            port_opt,
            mode_opt,
            c.run(function(ctx)
              captured = {
                verbose = ctx.args.verbose,
                port = ctx:get(port_opt),
                mode = ctx.args.mode,
              }
            end),
          }),
        })),
      })

      local exit_code = app:run({ "-v", "deploy", "-p", "8080", "--mode", "production" }, { capture = true })
      h.assert.equal(exit_code, 0, "CLI ran with 0 exit code without Valua")
      h.assert.truthy(captured, "handler executed")
      h.assert.equal(captured.verbose, true)
      h.assert.equal(captured.port, 8080)
      h.assert.equal(type(captured.port), "number")
      h.assert.equal(captured.mode, "production")

      -- Validation failure without Valua
      h.assert.has_error(function()
        app:parse({ "deploy", "-p", "500" })
      end, "Validation failed", "fixture schema rejects port < 1000 without Valua")
    end)

    package.loaded["valua"] = orig_loaded
    package.preload["valua"] = orig_preload

    if not test_ok then
      error(test_err)
    end
  end)

end)
