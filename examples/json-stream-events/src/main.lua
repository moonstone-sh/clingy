#!/usr/bin/env lua
-- Add local Clingy library to search path
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
    name = "builder",
    version = "2.4.0",
    description = "Deterministic Build CLI with JSON Stream Support",

    c.root(c.node({
        c.inherit(
            c.flag("--json"),
            c.flag("-v", "--verbose")
        ),

        compile = c.node({
            c.arg("target", v.picklist({ "web", "desktop", "native" })),
            c.option("-o", "--output", v.string()),

            c.run(function(ctx)
                ctx:span("compilation", function()
                    ctx:progress("compile", 10, "Parsing source AST")
                    ctx:log("info", "Target platform: " .. ctx.args.target)
                    
                    ctx:progress("compile", 45, "Generating code artifacts")
                    ctx:progress("compile", 80, "Optimizing bytecode")
                    ctx:progress("compile", 100, "Artifacts written to dist/" .. ctx.args.target)
                end)

                return {
                    status = "success",
                    target = ctx.args.target,
                    artifacts = { "dist/" .. ctx.args.target .. "/bundle.bin" },
                    duration_ms = 42,
                }
            end),
        }),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Machine NDJSON Stream Demo: builder --json compile desktop -o dist ===")
    args = { "--json", "compile", "desktop", "-o", "dist" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
