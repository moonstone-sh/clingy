#!/usr/bin/env lua
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function format_integer(value, base)
  if value == 0 then return "0" end

  local negative = value < 0
  value = math.abs(value)
  local digits = {}
  while value > 0 do
    local remainder = value % base
    table.insert(digits, 1, DIGITS:sub(remainder + 1, remainder + 1))
    value = math.floor(value / base)
  end

  return (negative and "-" or "") .. table.concat(digits)
end

local CLI = c.create({
  name = "calculator",
  version = "0.1.0",
  description = "A base-aware two-operand calculator",
  c.root(c.node({
    c.inherit(c.flag("--json")),
    c.label("defines", c.repeated(c.define("-D", {
      c.label("name", c.capture(v.string())),
      c.separator({ "=", " " }),
      c.label("value", c.capture(v.integer())),
    }))),
    c.arg("operation", v.picklist({ "add", "subtract", "multiply", "divide" })),
    c.arg("left", v.string()),
    c.arg("right", v.string()),
    c.run(function(ctx)
      local base = 10
      for _, definition in ipairs(ctx.args.defines or {}) do
        if definition.name ~= "base" then
          error("unknown definition: " .. definition.name)
        end
        base = definition.value
      end
      if base < 2 or base > 36 then error("base must be an integer from 2 through 36") end

      local left, right = tonumber(ctx.args.left, base), tonumber(ctx.args.right, base)
      if not left or not right then error("operands must be valid integers in base " .. base) end
      local result
      if ctx.args.operation == "add" then result = left + right
      elseif ctx.args.operation == "subtract" then result = left - right
      elseif ctx.args.operation == "multiply" then result = left * right
       elseif right == 0 then error("cannot divide by zero")
       elseif left % right ~= 0 then error("division result must be an integer")
       else result = left / right end

       return {
         operation = ctx.args.operation,
         left = left,
         right = right,
         base = base,
         result = format_integer(result, base),
         result_decimal = result,
       }
    end),
  })),
})

os.exit(CLI:run(arg or {}))
