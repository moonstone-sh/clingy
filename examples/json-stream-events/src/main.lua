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
            c.complete(c.directory(), c.option("-o", "--output", v.string())),
            c.complete(c.values({
                { value = "debug", description = "Unoptimized build with debug symbols" },
                { value = "release", description = "Standard optimized release build" },
                { value = "release-small", description = "Size-optimized binary" },
                { value = "release-fast", description = "Aggressive speed-optimized binary" },
            }), c.option("-p", "--profile")),
            c.complete(c.none(), c.option("--secret-token")),

            c.run(function(ctx)
                ctx:span("compilation", function()
                    ctx:progress("compile", 10, "Parsing source AST")
                    ctx:log("info", string.format("Target: %s (profile=%s)", ctx.args.target, ctx.args.profile or "debug"))
                    
                    ctx:progress("compile", 45, "Generating code artifacts")
                    ctx:progress("compile", 80, "Optimizing bytecode")
                    ctx:progress("compile", 100, "Artifacts written to dist/" .. ctx.args.target)
                end)

                return {
                    status = "success",
                    target = ctx.args.target,
                    profile = ctx.args.profile or "debug",
                    artifacts = { "dist/" .. ctx.args.target .. "/bundle.bin" },
                    duration_ms = 42,
                }
            end),
        }, { description = "Compile target platform with telemetry" }),

        -- Subcommand: completion
        completion = c.node({
            c.arg("shell", v.picklist({ "bash", "zsh", "fish", "powershell" })),

            c.run(function(ctx)
                local script = ctx.app:completion_script(ctx.args.shell, "builder")
                io.write(script, "\n")
            end),
        }, { description = "Generate shell completion script for bash, zsh, fish, or powershell" }),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Machine NDJSON Stream Demo: builder --json compile desktop -o dist ===")
    args = { "--json", "compile", "desktop", "-o", "dist" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
