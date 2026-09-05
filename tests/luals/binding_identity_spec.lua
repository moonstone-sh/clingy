local h = require("tests.harness")
local clingy = require("clingy")
local c = clingy.c
local v = require("valua")

h.describe("Binding Identity & ctx:get() Resolution", function()

  h.it("resolves local arg, option, and flag by binding reference", function()
    local dir_arg = c.arg("dirname")
    local port_opt = c.option("-p", "--port", v.pipe(v.string(), v.transform(tonumber)))
    local force_flag = c.flag("-f", "--force")

    local captured = {}

    local app = c.create({
      name = "test-app",
      c.root(c.node({
        dir_arg,
        port_opt,
        force_flag,

        c.run(function(ctx)
          captured.dirname = ctx:get(dir_arg)
          captured.port = ctx:get(port_opt)
          captured.force = ctx:get(force_flag)
          captured.by_string = ctx:get("dirname")
        end),
      })),
    })

    local code = app:run({ "my-dir", "--port", "8080", "--force" })
    h.assert.equal(code, 0, "app execution succeeded")
    h.assert.equal(captured.dirname, "my-dir", "positional arg resolved by binding")
    h.assert.equal(captured.port, 8080, "transformed option resolved by binding to number")
    h.assert.equal(captured.force, true, "flag resolved by binding to boolean true")
    h.assert.equal(captured.by_string, "my-dir", "string fallback works")
  end)

  h.it("resolves absent option and flag to nil and false", function()
    local opt = c.option("-o", "--output")
    local flag = c.flag("-v", "--verbose")

    local captured = {}

    local app = c.create({
      name = "test-app",
      c.root(c.node({
        opt,
        flag,

        c.run(function(ctx)
          captured.output = ctx:get(opt)
          captured.verbose = ctx:get(flag)
        end),
      })),
    })

    local code = app:run({})
    h.assert.equal(code, 0, "app execution succeeded")
    h.assert.is_nil(captured.output, "absent option resolves to nil")
    h.assert.equal(captured.verbose, false, "absent flag resolves to false")
  end)

  h.it("resolves inherited options from ancestor nodes along route", function()
    local global_verbose = c.flag("-v", "--verbose")
    local global_config = c.option("-c", "--config")
    local sub_target = c.arg("target")

    local captured = {}

    local app = c.create({
      name = "test-app",
      c.root(c.node({
        c.inherit(
          global_verbose,
          global_config
        ),

        build = c.node({
          sub_target,

          c.run(function(ctx)
            captured.verbose = ctx:get(global_verbose)
            captured.config = ctx:get(global_config)
            captured.target = ctx:get(sub_target)
          end),
        }),
      })),
    })

    local code = app:run({ "-v", "--config", "build.toml", "build", "core" })
    h.assert.equal(code, 0, "app execution succeeded")
    h.assert.equal(captured.verbose, true, "inherited flag resolved from ancestor")
    h.assert.equal(captured.config, "build.toml", "inherited option resolved from ancestor")
    h.assert.equal(captured.target, "core", "local leaf arg resolved")
  end)

  h.it("resolves cardinality-wrapped bindings (repeated, required, optional)", function()
    local headers = c.repeated(c.option("-H", "--header"))
    local req_opt = c.required(c.option("-t", "--token"))
    local opt_arg = c.optional(c.arg("extra"))

    local captured = {}

    local app = c.create({
      name = "test-app",
      c.root(c.node({
        headers,
        req_opt,
        opt_arg,

        c.run(function(ctx)
          captured.headers = ctx:get(headers)
          captured.token = ctx:get(req_opt)
          captured.extra = ctx:get(opt_arg)
        end),
      })),
    })

    local code = app:run({ "-H", "k1: v1", "-H", "k2: v2", "--token", "secret123" })
    h.assert.equal(code, 0, "app execution succeeded")
    h.assert.equal(#captured.headers, 2, "repeated options resolved to array of 2 elements")
    h.assert.equal(captured.headers[1], "k1: v1", "first repeated item matches")
    h.assert.equal(captured.headers[2], "k2: v2", "second repeated item matches")
    h.assert.equal(captured.token, "secret123", "required option matches")
    h.assert.is_nil(captured.extra, "omitted optional positional resolves to nil")
  end)

  h.it("returns nil for unmounted bindings or sibling command bindings", function()
    local unmounted_binding = c.flag("-x", "--unmounted")
    local sibling_binding = c.arg("sibling_arg")

    local captured = {}

    local app = c.create({
      name = "test-app",
      c.root(c.node({
        cmd1 = c.node({
          sibling_binding,
          c.run(function(ctx) end),
        }),
        cmd2 = c.node({
          c.run(function(ctx)
            captured.unmounted = ctx:get(unmounted_binding)
            captured.sibling = ctx:get(sibling_binding)
          end),
        }),
      })),
    })

    local code = app:run({ "cmd2" })
    h.assert.equal(code, 0, "cmd2 executed")
    h.assert.is_nil(captured.unmounted, "unmounted binding returns nil")
    h.assert.is_nil(captured.sibling, "sibling node binding returns nil on cmd2")
  end)

end)
