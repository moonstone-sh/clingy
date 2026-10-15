-- Narrow Valua imports: only the schema constructors this CLI uses.
local string_ = require("valua.schemas.string")
local integer = require("valua.schemas.integer")
return { name = string_(), greeting = string_(), times = integer() }
