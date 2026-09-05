#!/usr/bin/env lua
-- Add src to package.path
package.path = "src/?.lua;src/?/init.lua;../valua/src/?.lua;../valua/src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

-- Define Valua schemas for CLI arguments
local Profile = v.describe(
    v.picklist({ "development", "production", "test" }),
    "Target environment profile"
)

local Define = v.describe(
    v.string(),
    "Build-time definition in KEY=VALUE format"
)

-- Handlers
local function run_instant(ctx)
    ctx:log("info", "Executing instant initialization...")
    ctx:progress("init", 50, "Setting up runtime environment")
    ctx:log("info", string.format("Profile: %s, Now: %s, JSON: %s, Verbose: %s",
        tostring(ctx.args.profile),
        tostring(ctx.args.now),
        tostring(ctx.args.json),
        tostring(ctx.args.verbose)
    ))
    ctx:progress("init", 100, "Initialized successfully")
    return { status = "initialized", profile = ctx.args.profile, now = ctx.args.now }
end

local function run_build(ctx)
    ctx:log("info", "Starting build...")
    local defines = ctx.args.define or {}
    for i, def in ipairs(defines) do
        ctx:log("info", string.format("  [Define %d] %s", i, def))
    end
    return { status = "built", definitions = defines }
end

local function run_legacy(ctx)
    ctx:log("info", string.format("Executing ordered pipeline: source=%s -> destination=%s (prepare=%s, commit=%s)",
        ctx.args.source, ctx.args.destination, tostring(ctx.args.prepare), tostring(ctx.args.commit)))
    return { status = "migrated", source = ctx.args.source, destination = ctx.args.destination }
end

-- Declarative CLI Definition (Section 47)
local CLI = c.create({
    name = "meteorite",
    version = "0.1.0",
    description = "Meteorite HTTP & Microservice Framework CLI",

    c.root(c.node({
        -- Root inheritance: passed down to all descendants
        c.inherit(
            c.interspersed(),
            c.short_clusters(),
            c.flag("-v", "--verbose"),
            c.flag("-q", "--quiet")
        ),

        -- 'init' subcommand
        init = c.node({
            -- Subtree inheritance: --json is visible to 'init' and its descendants (like 'instant')
            c.inherit(
                c.flag("--json")
            ),

            -- Positional argument owned by 'init'
            c.arg("profile", Profile),

            -- 'instant' nested subcommand
            instant = c.node({
                c.flag("-n", "--now"),

                c.signals({
                    interrupt = function(ctx)
                        ctx:log("warn", "Interrupt signal received in instant init")
                        return c.signal.shutdown()
                    end,
                    terminate = function()
                        return c.signal.shutdown()
                    end,
                }),

                c.run(run_instant),
            }, {
                description = "Instantly scaffold project without interactive prompts",
            }),
        }, {
            description = "Initialize a Meteorite project",
        }),

        -- 'build' subcommand with repeated options
        build = c.node({
            c.repeated(
                c.option("-D", "--define", Define)
            ),

            c.run(run_build),
        }, {
            description = "Compile and build project artifacts",
        }),

        -- 'legacy' subcommand with strict ordered grammar
        legacy = c.node({
            c.ordered(),

            c.flag("--prepare"),
            c.arg("source", v.string()),
            c.flag("--commit"),
            c.arg("destination", v.string()),

            c.run(run_legacy),
        }, {
            description = "Execute legacy step-ordered pipeline",
        }),
    })),
})

-- If run directly from terminal
local args = arg or {}
if #args == 0 then
    -- Demo default run
    print("=== Running Meteorite Demo: meteorite init development instant -vn ===")
    args = { "init", "development", "instant", "-vn" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
