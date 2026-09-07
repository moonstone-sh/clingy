local h = require("tests.harness")
local plugin = require("luals.plugin")

h.describe("LuaLS Plugin — Static Analysis, Type Injection & Performance", function()

  h.it("extracts positional arguments, options, flags, and repeated wrappers", function()
    local sample_code = [[
      local c = require("clingy")
      ---@type standard_schema.Schema<any, string>
      local Directory = v.string()
      ---@type standard_schema.Schema<any, string>
      local Header = v.string()

      return c.node({
        c.arg("dirname", Directory),
        c.flag("-f", "--force"),
        c.repeated(
          c.option("-H", "--header", Header)
        ),
        c.required(
          c.option("-t", "--token")
        ),
        c.passthrough("extra"),

        c.run(function(ctx)
          local d = ctx.args.dirname
        end),
      })
    ]]

    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.dirname, "string", "extracted positional arg with schema")
    h.assert.equal(fields.force, "boolean", "extracted boolean flag")
    h.assert.equal(fields.header, "(string)[]|nil", "extracted repeated option")
    h.assert.equal(fields.token, "string", "extracted required option")
    h.assert.equal(fields.extra, "string[]", "extracted passthrough tokens")
  end)

  h.it("uses explicit option and flag result keys in extracted context fields", function()
    local sample_code = [[
      local c = require("clingy")
      local v = require("valua")

      return c.node({
        c.inherit(c.flag("global_debug", "--debug")),
        c.flag("dry_run", "--dry-run", "-n"),
        c.option("output_path", "--output", "-o", v.string()),
        c.repeated(c.option("header_values", "--header", "-H", v.string())),
        c.run(function(ctx) end),
      })
    ]]

    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.global_debug, "boolean")
    h.assert.equal(fields.dry_run, "boolean")
    h.assert.equal(fields.output_path, "string|nil")
    h.assert.equal(fields.header_values, "(string)[]|nil")

    local transformed = plugin.process_text("file:///explicit-keys.lua", sample_code)
    h.assert.truthy(transformed:find("global_debug: boolean"))
    h.assert.truthy(transformed:find("dry_run: boolean"))
    h.assert.truthy(transformed:find("output_path: string|nil"))
    h.assert.truthy(transformed:find("header_values: %(string%)%[%]|nil"))
  end)

  h.it("extracts labelled composed captures as independently typed context fields", function()
    local sample_code = [[
      local c = require("clingy")
      local v = require("valua")
      return c.node({
        c.compose(
          c.label("environment", c.capture(v.string())),
          c.separator(":"), c.literal("database"), c.separator("="),
          c.label("database", c.capture(v.boolean()))
        ),
        c.run(function(ctx) end),
      })
    ]]

    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.environment, "string")
    h.assert.equal(fields.database, "boolean")
  end)

  h.it("extracts repeated c.define records as typed context arrays", function()
    local sample_code = [[
      local c = require("clingy")
      local v = require("valua")
      return c.node({
        c.label("defines", c.repeated(c.define("-D", {
          c.label("name", c.capture(v.string())),
          c.separator({ "=", " ", "-" }),
          c.label("value", c.capture(v.string())),
        }))),
        c.run(function(ctx) end),
      })
    ]]
    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.defines, "{ name: string, value: string }[]|nil")
  end)

  h.it("extracts c.tail and keyword-safe c[\"end\"] forwarding", function()
    local file = assert(io.open("examples/advanced-grammar/src/main.lua", "r"))
    local source = file:read("*a")
    file:close()

    h.assert.truthy(source:find('c.tail("forwarded", "--", { c.forward("complete") })', 1, true),
      "fixture must use the canonical tail declaration spelling")

    local fields = plugin.extract_node_fields(source)
    h.assert.equal(fields.forwarded, "string[]", "end declaration injects forwarded tokens into ctx.args")

    local transformed = plugin.process_text("file:///examples/advanced-grammar/src/main.lua", source)
    h.assert.truthy(transformed:find("forwarded: string%[%]"),
      "advanced grammar handler receives forwarded: string[]")

    local alias_source = source:gsub("c%.tail", 'c["end"]')
    local alias_fields = plugin.extract_node_fields(alias_source)
    h.assert.equal(alias_fields.forwarded, "string[]", "deprecated alias retains forwarded typing")
  end)

  h.it("generates correct LuaCATS context annotation string", function()
    local fields = {
      dirname = "string",
      force = "boolean",
      header = "(string)[]|nil",
    }

    local annot = plugin.build_context_annotation(fields)
    h.assert.truthy(annot:find("clingy.Context<"), "contains clingy.Context annotation")
    h.assert.truthy(annot:find("dirname: string"), "contains dirname field")
    h.assert.truthy(annot:find("force: boolean"), "contains force field")
    h.assert.truthy(annot:find("header: %(string%)%[%]|nil"), "contains header field")
  end)

  h.it("transforms document text on c.run without crashing", function()
    local sample_code = [[
      local c = require("clingy")

      return c.node({
        c.arg("path"),
        c.flag("--verbose"),

        c.run(function(ctx)
          print(ctx.args.path)
        end),
      })
    ]]

    local transformed = plugin.process_text("file:///test.lua", sample_code)
    h.assert.truthy(transformed:find("---@cast ctx clingy.Context<"), "injected @cast context annotation into text")
    h.assert.truthy(transformed:find("path: string"), "injected path field")
    h.assert.truthy(transformed:find("verbose: boolean"), "injected verbose field")
  end)

  h.it("safely handles malformed code without raising errors (resilience test)", function()
    local malformed_code = [[
      local c = require("clingy")
      c.node({
        c.flag(
        c.arg(
        c.run(function(ctx)
    ]]

    local ok, res = pcall(function()
      return plugin.process_text("file:///malformed.lua", malformed_code)
    end)

    h.assert.truthy(ok, "pcall succeeded without crashing")
    h.assert.not_nil(res, "returned non-nil result")
  end)

  h.it("performance benchmark: scales efficiently on 10, 50, 100, and 500 commands", function()
    local generate_large_cli_source = function(num_commands)
      local lines = {
        'local c = require("clingy")',
        'local v = require("valua")',
        'return c.create({',
        '  name = "large-cli",',
        '  c.root(c.node({',
        '    c.inherit(c.flag("-v", "--verbose")),',
      }

      for i = 1, num_commands do
        table.insert(lines, string.format('    cmd_%d = c.node({', i))
        table.insert(lines, string.format('      c.arg("target_%d"),', i))
        table.insert(lines, string.format('      c.flag("--flag_%d"),', i))
        table.insert(lines, string.format('      c.option("-o%d", "--opt_%d"),', i, i))
        table.insert(lines, '      c.run(function(ctx)')
        table.insert(lines, string.format('        local t = ctx.args.target_%d', i))
        table.insert(lines, '      end),')
        table.insert(lines, '    }),')
      end

      table.insert(lines, '  })),')
      table.insert(lines, '})')
      return table.concat(lines, "\n")
    end

    local sizes = { 10, 50, 100, 500 }
    for _, count in ipairs(sizes) do
      local source = generate_large_cli_source(count)
      local start_time = os.clock()
      local result = plugin.process_text("file:///bench_" .. count .. ".lua", source)
      local elapsed_ms = (os.clock() - start_time) * 1000

      h.assert.not_nil(result, "processed benchmark source for count=" .. count)
      -- Assert reasonable execution latency (< 50ms even for 500 commands)
      h.assert.truthy(elapsed_ms < 50, string.format("latency for %d commands is %.2f ms (< 50 ms)", count, elapsed_ms))
    end
  end)
  h.it("unannotated anything.integer() evaluates strictly to unknown (asserts no constructor name guessing!)", function()
    local sample_code = [[
      local c = require("clingy")
      local Schema = anything.integer()

      return c.node({
        c.option("-p", "--port", Schema),
        c.arg("amount", anything.integer()),
        c.run(function(ctx) end),
      })
    ]]
    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.port, "unknown|nil", "unannotated option evaluates to unknown|nil")
    h.assert.equal(fields.amount, "unknown", "unannotated arg evaluates strictly to unknown")
  end)

  h.it("resolves ---@type standard_schema.Schema<any, number> to number", function()
    local sample_code = [[
      local c = require("clingy")
      ---@type standard_schema.Schema<any, number>
      local Count = anything.custom()

      return c.node({
        c.option("-c", "--count", Count),
        c.run(function(ctx) end),
      })
    ]]
    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.count, "number|nil", "extracted number|nil from ---@type standard_schema.Schema<any, number>")
  end)

  h.it("resolves ---@return standard_schema.Schema<any, string> to string", function()
    local sample_code = [[
      local c = require("clingy")
      ---@return standard_schema.Schema<any, string>
      local function make_schema()
        return foreign.validator()
      end
      local StrSchema = make_schema()

      return c.node({
        c.arg("name", StrSchema),
        c.option("--direct", make_schema()),
        c.run(function(ctx) end),
      })
    ]]
    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.name, "string", "extracted name as string from helper @return")
    h.assert.equal(fields.direct, "string|nil", "extracted direct inline call as string|nil")
  end)

  h.it("variable assignment tracing (local A = B)", function()
    local sample_code = [[
      local c = require("clingy")
      ---@type standard_schema.Schema<any, number>
      local B = foreign.create()
      local A = B

      return c.node({
        c.arg("val", A),
        c.run(function(ctx) end),
      })
    ]]
    local fields = plugin.extract_node_fields(sample_code)
    h.assert.equal(fields.val, "number", "recursively traced A = B to number")
  end)

  h.it("verifies accurate type injection on meteorite CLI example", function()
    local f = io.open("examples/meteorite/src/main.lua", "r")
    h.assert.not_nil(f, "examples/meteorite/src/main.lua must exist")
    local text = f:read("*a")
    f:close()

    local transformed = plugin.process_text("file:///examples/meteorite/src/main.lua", text)
    h.assert.truthy(transformed:find('profile: "development"|"production"|"test"'), "extracted exact literal union for profile")
    h.assert.truthy(transformed:find('define: %(string%)%[%]|nil'), "extracted repeated string option for define")
    h.assert.truthy(transformed:find('source: string'), "extracted string for source positional")
    h.assert.truthy(transformed:find('destination: string'), "extracted string for destination positional")
    h.assert.truthy(transformed:find('prepare: boolean'), "extracted boolean for prepare flag")
    h.assert.truthy(transformed:find('commit: boolean'), "extracted boolean for commit flag")
  end)

  h.it("proves complete decoupling: clingy/luals/library/valua.lua does NOT exist", function()
    local p1 = io.open("clingy/luals/library/valua.lua", "r")
    if p1 then p1:close() end
    h.assert.is_nil(p1, "clingy/luals/library/valua.lua must not exist")

    local p2 = io.open("src/clingy/luals/library/valua.lua", "r")
    if p2 then p2:close() end
    h.assert.is_nil(p2, "src/clingy/luals/library/valua.lua must not exist")

    local p3 = io.open("luals/library/valua.lua", "r")
    if p3 then p3:close() end
    h.assert.is_nil(p3, "luals/library/valua.lua must not exist")
  end)

end)
