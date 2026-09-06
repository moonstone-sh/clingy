#!/usr/bin/env lua
-- Add local Clingy library to search path
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
    name = "modes",
    version = "1.0.0",
    description = "Demonstration of Clingy Grammar Modes & Delimiters",

    c.root(c.node({
        -- Mode 1: Interspersed (default modern CLI mode)
        -- Options may appear anywhere relative to positionals
        inter = c.node({
            c.interspersed(),
            c.complete(c.file(), c.arg("src", v.string())),
            c.complete(c.path(), c.arg("dst", v.string())),
            c.complete(c.values({ "copy", "move", "link" }), c.option("-a", "--action")),
            c.flag("-f", "--force"),

            c.run(function(ctx)
                ctx:log("info", string.format("[Interspersed] src=%s dst=%s action=%s force=%s",
                    ctx.args.src, ctx.args.dst, tostring(ctx.args.action or "copy"), tostring(ctx.args.force)))
            end),
        }, { description = "Interspersed grammar (options anywhere)" }),

        -- Mode 2: Leading (options must precede positionals)
        leading = c.node({
            c.leading(),
            c.complete(c.file(), c.arg("src", v.string())),
            c.complete(c.path(), c.arg("dst", v.string())),
            c.complete(c.values({ "fast", "safe", "strict" }), c.option("-m", "--mode")),
            c.flag("-f", "--force"),

            c.run(function(ctx)
                ctx:log("info", string.format("[Leading] src=%s dst=%s mode=%s force=%s",
                    ctx.args.src, ctx.args.dst, tostring(ctx.args.mode or "safe"), tostring(ctx.args.force)))
            end),
        }, { description = "Leading grammar (options before positionals)" }),

        -- Mode 3: Ordered (strict declared sequence)
        ordered = c.node({
            c.ordered(),
            c.flag("--prepare"),
            c.complete(c.file(), c.arg("input", v.string())),
            c.flag("--commit"),
            c.complete(c.path(), c.arg("output", v.string())),

            c.run(function(ctx)
                ctx:log("info", string.format("[Ordered] prepare=%s input=%s commit=%s output=%s",
                    tostring(ctx.args.prepare), ctx.args.input, tostring(ctx.args.commit), ctx.args.output))
            end),
        }, { description = "Ordered grammar (strict declared sequence)" }),

        -- Mode 4: Passthrough with '--' delimiter
        exec = c.node({
            c.passthrough("forwarded"),

            c.run(function(ctx)
                ctx:log("info", "Raw passthrough tokens preserved exactly:")
                for i, token in ipairs(ctx.args.forwarded) do
                    ctx:log("info", string.format("  [%d] %s", i, token))
                end
            end),
        }, { description = "Raw passthrough with '--'" }),

        -- Subcommand: completion
        completion = c.node({
            c.arg("shell", v.picklist({ "bash", "zsh", "fish", "powershell" })),

            c.run(function(ctx)
                local script = ctx.app:completion_script(ctx.args.shell, "modes")
                io.write(script, "\n")
            end),
        }, { description = "Generate shell completion script for bash, zsh, fish, or powershell" }),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Demo 1: Interspersed mode with options after positionals (modes inter src.txt dst.txt -f) ===")
    CLI:run({ "inter", "src.txt", "dst.txt", "-f" })

    print("\n=== Demo 2: Leading mode with options first (modes leading -f src.txt dst.txt) ===")
    CLI:run({ "leading", "-f", "src.txt", "dst.txt" })

    print("\n=== Demo 3: Ordered mode (modes ordered --prepare in.bin --commit out.bin) ===")
    CLI:run({ "ordered", "--prepare", "in.bin", "--commit", "out.bin" })

    print("\n=== Demo 4: Passthrough delimiter (modes exec -- -Doptimize=ReleaseFast --flag 'arg with space') ===")
    CLI:run({ "exec", "--", "-Doptimize=ReleaseFast", "--flag", "arg with space" })
else
    local exit_code = CLI:run(args)
    os.exit(exit_code)
end
