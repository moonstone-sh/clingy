local h = require("tests.harness")

h.describe("LuaLS public library declarations", function()
  h.it("covers the current grammar constructors and tagged result shapes", function()
    local file = assert(io.open("luals/library/clingy.lua", "r"))
    local text = file:read("*a")
    file:close()

    for _, name in ipairs({
      "function c.forward(mode)",
      "function c.tail(name, terminator, opts)",
      "function c.passthrough(key)",
      "function c.label(name, declaration)",
      "function c.separator(separators, option, opts)",
      "function c.compose(...)",
      "function c.capture(schema)",
      "function c.literal(text)",
      "function c.define(prefix, fragments)",
    }) do
      h.assert.truthy(text:find(name, 1, true), "missing LuaLS declaration: " .. name)
    end

    h.assert.truthy(text:find('---@field tail fun(', 1, true),
      "missing canonical c.tail declaration")
    h.assert.truthy(text:find('---@deprecated Use c.tail instead.', 1, true),
      "missing deprecated c[\"end\"] annotation")
    h.assert.truthy(text:find('---@field ["end"] fun(', 1, true),
      'missing keyword-safe c["end"] declaration')
    for _, tag in ipairs({
      '---@class clingy.ForwardPolicy',
      '---@class clingy.EndDeclaration',
      '---@class clingy.DefineSeparator',
      '---@class clingy.ComposeSeparator',
      '---@class clingy.Literal',
    }) do
      h.assert.truthy(text:find(tag, 1, true), "missing tagged LuaLS type: " .. tag)
    end

    h.assert.truthy(text:find('{ [1]: clingy.Capture<N>, [2]: clingy.DefineSeparator, [3]: clingy.Capture<V> }', 1, true),
      "c.define fragment types must describe labelled captures and its separator")
    h.assert.truthy(text:find('---@return clingy.Binding<string[]>', 1, true),
      "c.passthrough must expose its string-array result")
  end)

  h.it("discriminates separator overloads used by the advanced grammar source", function()
    local library = assert(io.open("luals/library/clingy.lua", "r"))
    local declarations = library:read("*a")
    library:close()

    local example = assert(io.open("examples/advanced-grammar/src/main.lua", "r"))
    local source = example:read("*a")
    example:close()

    h.assert.truthy(source:find('c.separator({ "=", " " })', 1, true),
      "advanced grammar must exercise the table fragment form")
    h.assert.truthy(source:find('c.separator(":"), c.literal("database"), c.separator("=")', 1, true),
      "advanced grammar must exercise the one-string fragment form")
    h.assert.truthy(source:find('c.separator({ "=", ":", " " }, c.option("--profile", v.string()))', 1, true),
      "advanced grammar must exercise the option-wrapper form")

    -- The required Binding parameter on the implementation signature excludes
    -- fragment calls from the wrapper path. LuaLS then selects the matching
    -- fragment overload rather than exposing a broad result union to c.define.
    h.assert.truthy(declarations:find('---@overload fun(separators: string[], opts?: { trim?: boolean }): clingy.DefineSeparator', 1, true),
      "table separator fragments must overload to DefineSeparator")
    h.assert.truthy(declarations:find('---@overload fun(text: string, opts?: { trim?: boolean }): clingy.ComposeSeparator', 1, true),
      "one-string separator fragments must overload to ComposeSeparator")
    h.assert.truthy(declarations:find('---@param separators string|string[]\n---@param option clingy.Binding<any>\n---@param opts? { trim?: boolean }\n---@return clingy.Binding<any>\nfunction c.separator(separators, option, opts) end', 1, true),
      "option-wrapper separator calls must have a concrete Binding signature")
  end)
end)
