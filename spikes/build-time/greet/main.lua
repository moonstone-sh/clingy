-- Built path: load the compiled router as data; no DSL, compiler, help or
-- completion code, and no Valua reflection while parsing.
local built = require("greet.graph")
local adapter = require("clingy.adapter")
local compat = require("clingy.compat")

-- Spike-only: Clingy would read the precomputed kind itself.
local kinds = {}
for _, pair in ipairs(built.coerce) do kinds[pair[1]] = pair[2] end
local reflect = adapter.coerce
adapter.coerce = function(token, schema)
  local kind = kinds[schema]
  if type(token) ~= "string" or kind == nil then return reflect(token, schema) end
  if kind == "integer" then
    if token:match("^[+-]?%d+$") then local n = tonumber(token); return n and compat.to_integer(n) or n end
  elseif kind == "number" then return tonumber(token) or token
  elseif kind == "boolean" then
    local lower = token:lower()
    if lower == "true" or lower == "1" or lower == "yes" or lower == "on" then return true end
    if lower == "false" or lower == "0" or lower == "no" or lower == "off" then return false end
  end
  return token
end

local app = require("clingy.app").create_app(built.router, { name = "greet" })
return function(argv) return app:run(argv) end
