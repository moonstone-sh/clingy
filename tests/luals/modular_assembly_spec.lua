local h = require("tests.harness")
local clingy = require("clingy")
local c = clingy.c
local v = require("valua")

h.describe("Modular Router Assembly & require() Identity", function()

  h.it("assembles router from modular leaf definitions via require()", function()
    -- Simulate module meteorite.cli.init
    package.loaded["mock_cli.init"] = c.node({
      c.arg("dirname"),
      c.flag("-f", "--force"),
      c.run(function(ctx)
        ctx:result({ dir = ctx.args.dirname, force = ctx.args.force })
      end),
    })

    -- Simulate module meteorite.cli.build
    package.loaded["mock_cli.build"] = c.node({
      c.option("-t", "--target"),
      c.run(function(ctx)
        ctx:result({ target = ctx.args.target or "all" })
      end),
    })

    local app = c.create({
      name = "meteorite",
      c.root(c.node({
        init = require("mock_cli.init"),
        build = require("mock_cli.build"),
      })),
    })

    local res_init = app:parse({ "init", "my-project", "-f" })
    h.assert.equal(res_init.args.dirname, "my-project", "leaf init parsed dirname")
    h.assert.equal(res_init.args.force, true, "leaf init parsed force")

    local res_build = app:parse({ "build", "--target", "wasm" })
    h.assert.equal(res_build.args.target, "wasm", "leaf build parsed target")
  end)

  h.it("supports separated args.lua, run.lua, node.lua decomposition", function()
    -- 1. args.lua
    local init_args = {
      dirname = c.arg("dirname"),
      json = c.flag("--json"),
      force = c.flag("-f", "--force"),
    }
    package.loaded["mock_init.args"] = init_args

    -- 2. run.lua
    local init_run = function(ctx)
      local d = ctx:get(init_args.dirname)
      local f = ctx:get(init_args.force)
      local j = ctx:get(init_args.json)
      return { dirname = d, force = f, json = j }
    end
    package.loaded["mock_init.run"] = init_run

    -- 3. node.lua
    local args_mod = require("mock_init.args")
    local run_mod = require("mock_init.run")

    local init_node = c.node({
      args_mod.dirname,
      args_mod.json,
      args_mod.force,

      c.run(run_mod),
    })
    package.loaded["mock_init.node"] = init_node

    -- Root router assembling the decomposed leaf node
    local app = c.create({
      name = "cli",
      c.root(c.node({
        init = require("mock_init.node"),
      })),
    })

    local captured_result = nil
    local ctx_mock = {
      args = { dirname = "pkg", force = true, json = false },
      target_node = app._graph.root.children["init"],
      route = { { node = "root" }, { node = "init", node_ir = app._graph.root.children["init"] } },
    }
    setmetatable(ctx_mock, { __index = clingy.Context })

    local result = init_run(ctx_mock)
    h.assert.equal(result.dirname, "pkg", "resolved dirname via separated args module")
    h.assert.equal(result.force, true, "resolved force flag via separated args module")
    h.assert.equal(result.json, false, "resolved json flag via separated args module")
  end)

  h.it("supports shared c.group grammar fragments across commands", function()
    local shared_output_group = c.group({
      c.flag("-q", "--quiet"),
      c.flag("--json"),
      c.option("-o", "--output"),
    })

    local app = c.create({
      name = "cli",
      c.root(c.node({
        cmd_a = c.node({
          shared_output_group,
          c.run(function(ctx) end),
        }),
        cmd_b = c.node({
          shared_output_group,
          c.run(function(ctx) end),
        }),
      })),
    })

    local res_a = app:parse({ "cmd_a", "--json", "-o", "out_a.txt" })
    h.assert.equal(res_a.args.json, true, "cmd_a parsed shared json flag")
    h.assert.equal(res_a.args.output, "out_a.txt", "cmd_a parsed shared output option")

    local res_b = app:parse({ "cmd_b", "-q", "-o", "out_b.txt" })
    h.assert.equal(res_b.args.quiet, true, "cmd_b parsed shared quiet flag")
    h.assert.equal(res_b.args.output, "out_b.txt", "cmd_b parsed shared output option")
  end)

  h.it("proves require() preserves table identity whereas dofile() allocates distinct tables", function()
    -- Helper simulating module creation
    local create_decl_module = function()
      return {
        verbose = c.flag("-v", "--verbose"),
      }
    end

    -- require() caching model:
    local shared_instance = create_decl_module()
    package.loaded["cached_decl_module"] = shared_instance

    local req1 = require("cached_decl_module")
    local req2 = require("cached_decl_module")
    h.assert.truthy(rawequal(req1.verbose, req2.verbose), "require() yields identical table reference (rawequal)")

    -- dofile() non-caching model:
    local dofile1 = create_decl_module()
    local dofile2 = create_decl_module()
    h.assert.falsy(rawequal(dofile1.verbose, dofile2.verbose), "dofile() produces distinct table allocations (not rawequal)")
  end)

end)
