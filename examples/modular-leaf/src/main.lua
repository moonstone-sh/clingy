#!/usr/bin/env lua
package.path = "src/?.lua;src/?/init.lua;../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")

local CLI = c.create({
    name = "modular-cli",
    version = "1.0.0",
    description = "Modular Router Assembly Showcase",

    c.root(c.node({
        c.inherit(
            c.flag("-v", "--verbose")
        ),

        init = require("cli.init"),
        build = require("cli.build.node"),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Modular Demo: modular-cli init my-project -f ===")
    args = { "init", "my-project", "-f" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
