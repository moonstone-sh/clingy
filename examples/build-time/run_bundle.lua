#!/usr/bin/env lua
local run = dofile((arg[0]:match("^(.*/)") or "./") .. "greet.bundle.lua")
os.exit(run(arg))
