#!/usr/bin/env lua
-- Add local Clingy library to search path
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

local CLI = c.create({
    name = "runner",
    version = "1.0.0",
    description = "Subprocess & Lifecycle Scopes Example",

    c.root(c.node({
        c.inherit(
            c.flag("-v", "--verbose")
        ),

        worker = c.node({
            c.complete(c.values({ "1", "2", "4", "8", "16" }), c.option("-t", "--tasks", v.integer())),
            c.complete(c.directory(), c.option("-w", "--workdir")),

            -- Dynamic context-aware completion: proposes job names based on parsed --tasks count
            c.complete(c.dynamic(function(ctx)
                local count = tonumber(ctx.args.tasks) or 4
                local jobs = {}
                for i = 1, count do
                    table.insert(jobs, string.format("job-%02d", i))
                end
                return jobs
            end), c.arg("job_name", v.optional(v.string()))),

            c.run(function(ctx)
                ctx:log("info", string.format("Starting task execution with managed scope (tasks=%s, job=%s, workdir=%s)...",
                    tostring(ctx.args.tasks or 1), tostring(ctx.args.job_name or "default"), tostring(ctx.args.workdir or ".")))

                -- Create a managed resource scope
                return ctx:scope(function(scope)
                    -- Register cleanup handlers in LIFO order
                    scope:defer(function()
                        ctx:log("info", "[Cleanup 1] Flushing temporary logs")
                    end)

                    scope:defer(function()
                        ctx:log("info", "[Cleanup 2] Releasing network socket")
                    end)

                    scope:defer(function()
                        ctx:log("info", "[Cleanup 3] Removing lock file")
                    end)

                    -- Spawn a managed child process
                    ctx:log("info", "Spawning child process (uname -s)...")
                    local proc = ctx:spawn({
                        argv = { "uname", "-s" },
                        mode = "capture",
                    })

                    ctx:log("info", "Child state before wait: " .. proc:state())
                    local exit_code, stdout, stderr = proc:wait()
                    ctx:log("info", "Child state after wait: " .. proc:state())
                    ctx:log("info", "Child output: " .. (stdout:gsub("%s+$", "")))

                    ctx:log("info", "Scope completing — defer callbacks will now unwind in reverse order...")
                    return { status = "success", os = stdout:gsub("%s+$", "") }
                end)
            end),
        }, {
            description = "Run worker tasks within managed scope",
        }),

        -- Subcommand: completion
        completion = c.node({
            c.arg("shell", v.picklist({ "bash", "zsh", "fish", "powershell" })),

            c.run(function(ctx)
                local script = ctx.app:completion_script(ctx.args.shell, "runner")
                io.write(script, "\n")
            end),
        }, { description = "Generate shell completion script for bash, zsh, fish, or powershell" }),
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Subprocess Lifecycle Demo: runner worker -t 4 -v ===")
    args = { "worker", "-t", "4", "-v" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
