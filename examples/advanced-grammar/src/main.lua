#!/usr/bin/env lua
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
  name = "advanced-grammar",
  version = "0.1.0",
  description = "Structured forms, option forms, and forwarding",
  root = c.node({
    c.arg({
      key = "target",
      form = c.sequence({
        c.capture({ key = "environment", schema = v.string() }),
        c.literal({ text = ":database=" }),
        c.capture({ key = "database", schema = v.boolean() }),
      }),
    }),
    c.option({
      key = "defines", aliases = { "-D" }, occurs = { min = 0, max = "many" },
      form = c.sequence({
        c.capture({ key = "name", schema = v.string() }),
        c.choice({
          c.sequence({ c.literal({ text = "=" }), c.capture({ key = "value", schema = v.string() }) }),
          c.sequence({ c.next_token(), c.capture({ key = "value", schema = v.string() }) }),
        }),
      }),
    }),
    c.option({ key = "profile", aliases = { "--profile" }, value = { schema = v.string(), attached = { "=", ":" }, detached = true } }),
    c.tail("forwarded", "--", { c.forward("complete") }),
    c.run(function(ctx)
      local result = {
        environment = ctx.args.target.environment,
        database = ctx.args.target.database,
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
  }),
})

local argv = arg or {}
if #argv == 0 then
  argv = { "dev:database=true", "-Dmode=fast", "-Dfeature", "on", "--profile:demo", "--", "tool", "--verbose" }
end
os.exit(CLI:run(argv))
