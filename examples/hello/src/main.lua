#!/usr/bin/env lua
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
  name = "hello",
  version = "0.1.0",
  description = "A small positional greeting",
  c.root(c.node({
    c.optional(c.flag("--shout")),
    c.arg("name", v.string()),
    c.run(function(ctx)
      local greeting = "Hello, " .. ctx.args.name .. "!"
      if ctx.args.shout then greeting = string.upper(greeting) end
      local result = { greeting = greeting, name = ctx.args.name, shout = ctx.args.shout or false }
      -- Keep the structured return for machine output, while the message makes
      -- the same invocation useful in a human-readable terminal.
      ctx:result(result, greeting)
      return result
    end),
  })),
})

os.exit(CLI:run(arg or {}))
