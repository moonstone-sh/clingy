#!/usr/bin/env lua
-- Add local Clingy library to search path
package.path = "../../src/?.lua;../../src/?/init.lua;" .. package.path

local c = require("clingy")
local v = require("valua")

-- Define Valua schemas for CLI arguments
local Profile = v.describe(v.picklist({ "development", "production", "test" }), "Target environment profile")

local Define = v.describe(v.string(), "Build-time definition in KEY=VALUE format")

-- Declarative CLI Definition
local CLI = c.create({
	name = "meteorite",
	version = "0.1.0",
	description = "Meteorite HTTP & Microservice Framework CLI",

	c.root(c.node({
		-- Root inheritance: passed down to all descendants
		c.inherit(c.interspersed(), c.short_clusters(), c.flag({ key = "verbose", aliases = { "-v", "--verbose" } }), c.flag({ key = "quiet", aliases = { "-q", "--quiet" } })),

		-- 'init' subcommand
		init = c.node({
			-- Subtree inheritance: --json is visible to 'init' and its descendants (like 'instant')
			c.inherit(c.flag({ key = "json", aliases = { "--json" } })),

			-- Positional argument owned by 'init' (schema-derived picklist completion)
			c.arg({ key = "profile", schema = Profile }),

			-- Filesystem and static value completion options
			c.option({ key = "dest", aliases = { "-d", "--dest" }, value = { schema = v.string() }, complete = c.directory() }),
			c.option({ key = "template", aliases = { "-t", "--template" }, complete = c.values({ "minimal", "microservice", "full-stack", "api-gateway" }) }),

			-- 'instant' nested subcommand
			instant = c.node({
				c.flag({ key = "now", aliases = { "-n", "--now" } }),

				c.signals({
					interrupt = function(ctx)
						ctx:log("warn", "Interrupt signal received in instant init")
						return c.signal.shutdown()
					end,
					terminate = function()
						return c.signal.shutdown()
					end,
				}),

				c.run(function(ctx)
					ctx:log("info", "Executing instant initialization...")
					ctx:progress("init", 50, "Setting up runtime environment")
					ctx:log(
						"info",
						string.format(
							"Profile: %s, Now: %s, JSON: %s, Verbose: %s",
							tostring(ctx.args.profile),
							tostring(ctx.args.now),
							tostring(ctx.args.json),
							tostring(ctx.args.verbose)
						)
					)
					ctx:progress("init", 100, "Initialized successfully")
					return { status = "initialized", profile = ctx.args.profile, now = ctx.args.now }
				end),
			}, {
				description = "Instantly scaffold project without interactive prompts",
			}),
		}, {
			description = "Initialize a Meteorite project",
		}),

		-- 'build' subcommand with repeated options and completions
		build = c.node({
			c.option({ key = "define", aliases = { "-D", "--define" }, value = { schema = Define }, occurs = { min = 0, max = "many" }, complete = c.values({ "ENV=development", "ENV=production", "PORT=8080", "DEBUG=true" }) }),
			c.option({ key = "config", aliases = { "-c", "--config" }, complete = c.file({ extensions = { "lua" } }) }),
			c.option({ key = "output_dir", aliases = { "-o", "--output-dir" }, complete = c.directory() }),

			c.run(function(ctx)
				ctx:log("info", "Starting build...")
				local defines = ctx.args.define or {}
				for i, def in ipairs(defines) do
					ctx:log("info", string.format("  [Define %d] %s", i, def))
				end
				return { status = "built", definitions = defines }
			end),
		}, {
			description = "Compile and build project artifacts",
		}),

		-- 'legacy' subcommand with strict ordered grammar and path completions
		legacy = c.node({
			c.ordered(),

			c.flag({ key = "prepare", aliases = { "--prepare" } }),
			c.arg({ key = "source", schema = v.string(), complete = c.file() }),
			c.flag({ key = "commit", aliases = { "--commit" } }),
			c.arg({ key = "destination", schema = v.string(), complete = c.path() }),

			c.run(function(ctx)
				ctx:log(
					"info",
					string.format(
						"Executing ordered pipeline: source=%s -> destination=%s (prepare=%s, commit=%s)",
						ctx.args.source,
						ctx.args.destination,
						tostring(ctx.args.prepare),
						tostring(ctx.args.commit)
					)
				)
				return { status = "migrated", source = ctx.args.source, destination = ctx.args.destination }
			end),
		}, {
			description = "Execute legacy step-ordered pipeline",
		}),

		-- 'completion' subcommand to generate shell scripts
		completion = c.node({
			c.arg({ key = "shell", schema = v.picklist({ "bash", "zsh", "fish", "powershell" }) }),

			c.run(function(ctx)
				local script = ctx.app:completion_script(ctx.args.shell, "meteorite")
				io.write(script, "\n")
			end),
		}, {
			description = "Generate shell completion script for bash, zsh, fish, or powershell",
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
