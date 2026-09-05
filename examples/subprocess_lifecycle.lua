#!/usr/bin/env lua
-- Add src to package.path
package.path = "src/?.lua;src/?/init.lua;../valua/src/?.lua;../valua/src/?/init.lua;" .. package.path

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
            c.option("-t", "--tasks", v.integer()),

            c.run(function(ctx)
                ctx:log("info", "Starting task execution with managed scope...")

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
                    local proc = scope:spawn({
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
    })),
})

local args = arg or {}
if #args == 0 then
    print("=== Running Subprocess Lifecycle Demo: runner worker -t 4 -v ===")
    args = { "worker", "-t", "4", "-v" }
end

local exit_code = CLI:run(args)
os.exit(exit_code)
