-- Runtime module for the built-CLI fixture: everything here is referenced by
-- name from the built graph.
-- Individual Valua modules, so a built CLI doesn't load all of Valua.
local pipe = require("valua.methods.pipe")
local integer = require("valua.schemas.integer")
local check = require("valua.actions.check")

local M = { calls = {} }

function M.add(ctx) M.calls[#M.calls + 1] = { "add", ctx.args } end
function M.run(ctx) M.calls[#M.calls + 1] = { "run", ctx.args } end
function M.names() return { "alpha", "beta" } end

-- A schema Clingy can't recreate (it has a function check), so it is exported.
M.even = pipe(integer(), check(function(n) return n % 2 == 0 end, "must be even"))

return M
