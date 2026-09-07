#!/usr/bin/env lua
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
  name = "advanced-grammar",
  version = "0.1.0",
  description = "Composed tokens, definitions, separators, and forwarding",
  c.root(c.node({
    c.compose(
      c.label("environment", c.capture(v.string())),
      c.separator(":"), c.literal("database"), c.separator("="),
      c.label("database", c.capture(v.boolean()))
    ),
    c.label("defines", c.repeated(c.define("-D", {
      c.label("name", c.capture(v.string())),
      c.separator({ "=", " " }),
      c.label("value", c.capture(v.string())),
    }))),
    c.separator({ "=", ":", " " }, c.option("--profile", v.string())),
    c.tail("forwarded", "--", { c.forward("complete") }),
    c.run(function(ctx)
      local result = {
        environment = ctx.args.environment,
        database = ctx.args.database,
        profile = ctx.args.profile or "default",
        defines = ctx.args.defines or {},
        forwarded = ctx.args.forwarded or {},
      }
      ctx:log("info", string.format(
        "Parsed environment=%s database=%s profile=%s",
        result.environment, tostring(result.database), result.profile
      ))
      ctx:log("info", "Forwarded tokens: " .. table.concat(result.forwarded, " "))
      ctx:result(result, string.format(
        "Advanced grammar: %s (database=%s, profile=%s)",
        result.environment, tostring(result.database), result.profile
      ))
      return result
    end),
  })),
})

local argv = arg or {}
if #argv == 0 then
  argv = { "dev:database=true", "-Dmode=fast", "-Dfeature", "on", "--profile:demo", "--", "tool", "--verbose" }
end
os.exit(CLI:run(argv))
