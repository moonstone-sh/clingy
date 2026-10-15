local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")
local build = require("clingy.build")
local runtime = require("clingy.runtime")

local describe, it, assert = h.describe, h.it, h.assert

local DECLARATION = "tests.fixtures.built.cli"
local MODULE = "tests.fixtures.built.out"

local load_chunk = loadstring or load

local function built_from(result, module)
  local chunk, err = load_chunk(result.modules[module], "=" .. module)
  if not chunk then error(err, 0) end
  return chunk()
end

local function fixture()
  local result = build.build({ declaration = DECLARATION, module = MODULE })
  return result, built_from(result, MODULE)
end

local function outcome(app, argv)
  local ok, parsed = pcall(app.parse, app, argv)
  if not ok then return { error = tostring(parsed):gsub("^.-:%d+: ", "") } end
  return { args = parsed.args }
end

-- A module that only exists while a test runs.
local function with_module(name, value, fn)
  package.loaded[name] = value
  local ok, err = pcall(fn)
  package.loaded[name] = nil
  if not ok then error(err, 0) end
end

describe("clingy.build and clingy.runtime", function()
  it("parses every argv exactly like c.create", function()
    local _, built = fixture()
    local dev = c.create(require(DECLARATION))
    local app = runtime.create(built)
    for _, argv in ipairs({
      { "add", "file" }, { "-v", "add", "dir", "-t", "a", "-t", "b" }, { "add", "dir", "-n", "4" },
      { "add", "dir", "-n", "3" }, { "add", "dir", "-n", "x" }, { "add", "nope" }, { "add" },
      { "add", "file", "--owner", "me", "--config", "x.toml" }, { "run", "s.lua", "--", "-x", "y" },
      { "run" }, { "--bogus" }, { "add", "file", "-v" },
    }) do
      assert.same(outcome(app, argv), outcome(dev, argv), table.concat(argv, " "))
    end
  end)

  it("runs the referenced handler", function()
    local _, built = fixture()
    local handlers = require("tests.fixtures.built.handlers")
    local before = #handlers.calls
    runtime.run(built, { "add", "file", "-t", "x" }, { presentation = c.null_host() })
    assert.equal(#handlers.calls, before + 1)
    assert.equal(handlers.calls[#handlers.calls][1], "add")
    assert.same(handlers.calls[#handlers.calls][2].tag, { "x" })
  end)

  it("references exports and recreates inline schemas and providers", function()
    local result = fixture()
    local source = result.modules[MODULE]
    assert.matches(source, 'require%("tests%.fixtures%.built%.handlers"%)%.even', "exported schema")
    assert.matches(source, 'require%("tests%.fixtures%.built%.handlers"%)%.add', "handler")
    assert.matches(source, 'require%("valua%.schemas%.picklist"%)%({ "file", "dir" }%)', "recreated schema")
    assert.matches(source, 'providers"%)%.dynamic%(require%("tests%.fixtures%.built%.handlers"%)%.names%)', "dynamic provider")
    assert.matches(source, 'providers"%)%.file%({ extensions = { "toml" } }%)', "file provider")
    assert.falsy(source:find("decl_map", 1, true), "identity-keyed lookups are not data")
  end)

  it("keeps the declared schema objects in the graph", function()
    local handlers = require("tests.fixtures.built.handlers")
    local graph = require("clingy.compiler").normalize(require(DECLARATION))
    assert.equal(graph.bindings["root.add:count"].schema, handlers.even)
  end)

  it("writes the same text every time", function()
    local first = build.build({ declaration = DECLARATION, module = MODULE })
    local second = build.build({ declaration = DECLARATION, module = MODULE })
    for path, text in pairs(first.files) do assert.equal(second.files[path], text, path) end
  end)

  it("generates typed args whose values are the result keys", function()
    local result = fixture()
    local args = built_from(result, MODULE .. ".args")
    assert.same(args.add, { config = "config", count = "count", kind = "kind", owner = "owner", tag = "tag", verbose = "verbose" })
    assert.same(args.run, { rest = "rest", script = "script", verbose = "verbose" })
    local text = result.modules[MODULE .. ".args"]
    assert.matches(text, '%-%-%-@field kind clingy%.Binding<"file"|"dir">')
    assert.matches(text, '%-%-%-@class tests%.fixtures%.built%.out%.args%.add%.values\n')
    assert.matches(text, '%-%-%-@field kind "file"|"dir"\n')
    assert.matches(text, '%-%-%-@class tests%.fixtures%.built%.out%.args%.add%.context: clingy%.Context\n%-%-%-@field args tests%.fixtures%.built%.out%.args%.add%.values')
    assert.matches(text, "%-%-%-@field tag clingy%.Binding<%(string%)%[%]|nil>")
    assert.matches(text, "%-%-%-@field verbose clingy%.Binding<boolean>")
    assert.matches(text, "%-%-%-@field script clingy%.Binding<string>\n")
  end)

  it("lets handlers require the args module before it exists", function()
    with_module("tests.fixtures.built.first_handlers", nil, function()
      package.preload["tests.fixtures.built.first_handlers"] = function()
        local args = require("tests.fixtures.built.first.args").root
        return { go = function(ctx) return ctx:get(args.name) end, key = args.name }
      end
      package.preload["tests.fixtures.built.first_cli"] = function()
        local handlers = require("tests.fixtures.built.first_handlers")
        return { name = "first", root = c.node({ c.arg({ key = "name", schema = v.string() }), c.run(handlers.go) }) }
      end
      local result = build.build({ declaration = "tests.fixtures.built.first_cli", module = "tests.fixtures.built.first" })
      assert.truthy(result.modules["tests.fixtures.built.first.args"])
      assert.is_nil(package.loaded["tests.fixtures.built.first.args"], "stand-in removed after the build")
      package.preload["tests.fixtures.built.first_handlers"] = nil
      package.preload["tests.fixtures.built.first_cli"] = nil
      package.loaded["tests.fixtures.built.first_cli"] = nil
    end)
  end)

  it("names the place of an inline function", function()
    with_module("tests.fixtures.built.inline_cli", { name = "inline", root = c.node({
      c.arg({ key = "name", schema = v.string() }),
      c.run(function() end),
    }) }, function()
      assert.has_error(function()
        build.build({ declaration = "tests.fixtures.built.inline_cli", module = "x.built" })
      end, "root%.nodes%.root%.handler.-exports? of a module")
    end)
  end)

  it("refuses an inline schema it cannot recreate", function()
    with_module("tests.fixtures.built.opaque_cli", { name = "opaque", root = c.node({
      c.arg({ key = "name", schema = v.pipe(v.string(), v.check(function() return true end)) }),
    }) }, function()
      assert.has_error(function()
        build.build({ declaration = "tests.fixtures.built.opaque_cli", module = "x.built" })
      end, "schema at root%.bindings%[root:name%]%.schema")
    end)
  end)

  it("rejects modules that are not in the built format", function()
    assert.has_error(function() runtime.load({ format = "clingy.command-graph.v0" }) end, "expected a clingy%.built%.v1")
  end)

  it("loads neither the DSL, the compiler, completion, help, nor all of Valua", function()
    local result = build.build({ declaration = DECLARATION, module = MODULE })
    local dir = os.tmpname()
    os.remove(dir)
    assert.truthy(os.execute('mkdir -p "' .. dir .. '/tests/fixtures/built/out"'))
    for path, text in pairs(result.files) do
      local f = io.open(dir .. "/" .. path, "w")
      f:write(text)
      f:close()
    end
    local interpreter = (arg and arg[-1]) or "lua"
    local script = ([[
      package.path = %q .. "/?.lua;" .. %q
      local runtime = require("clingy.runtime")
      runtime.run(require(%q), { "add", "file" }, { presentation = require("clingy.presentation").create_null_host() })
      local loaded = {}
      for name in pairs(package.loaded) do loaded[#loaded + 1] = name end
      table.sort(loaded)
      io.write(table.concat(loaded, " "))
    ]]):format(dir, package.path, MODULE)
    local f = io.open(dir .. "/probe.lua", "w")
    f:write(script)
    f:close()
    local pipe = io.popen(interpreter .. ' "' .. dir .. '/probe.lua" 2>&1')
    local loaded = " " .. pipe:read("*a") .. " "
    pipe:close()
    os.execute('rm -rf "' .. dir .. '"')
    assert.matches(loaded, " clingy%.runtime ", loaded)
    for _, name in ipairs({ "clingy", "clingy.dsl", "clingy.compiler", "clingy.help", "clingy.completion",
      "clingy.completion.partial_parser", "valua", "valua.methods.reflect" }) do
      assert.falsy(loaded:find(" " .. name:gsub("%.", "%%.") .. " "), name .. " should not load")
    end
  end)
end)
