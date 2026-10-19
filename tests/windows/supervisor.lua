package.path = "src/?.lua;src/?/init.lua;" .. package.path
require("moonstone.variants").install()
local opts = assert(loadfile(arg[2]))()
local supervisor = require("clingy.supervisor")
assert(supervisor.extension == ".ps1", "Windows flavor was not selected")
local script = supervisor.script(opts)
local file = assert(io.open(arg[1], "wb"))
file:write("\239\187\191", script)
file:close()
