#!/usr/bin/env lua
package.path = "src/?.lua;src/?/init.lua;../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

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

        completion = c.node({
            c.arg("shell", v.picklist({ "bash", "zsh", "fish", "powershell" })),
            c.run(function(ctx)
                local script = ctx.app:completion_script(ctx.args.shell, "modular-cli")
                io.write(script, "\n")
            end),
        }, { description = "Generate shell completion script for bash, zsh, fish, or powershell" }),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Modular Demo: modular-cli init my-project -f ===")
    args = { "init", "my-project", "-f" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
