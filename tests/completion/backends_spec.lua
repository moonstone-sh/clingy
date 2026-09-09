--[[
  tests/completion/backends_spec.lua
  Shell Completion Backends: Script generation and response rendering across
  Bash, Zsh, Fish, and PowerShell.
]]

local h = require("tests.harness")
local c = require("clingy")
local comp_mod = require("clingy.completion")
local response = comp_mod.response
local backends = comp_mod.backends

local describe, it = h.describe, h.it
local assert = h.assert

describe("Shell Completion Backends", function()

  describe("Script Generation (Thin Shims)", function()
    local app = c.create({
      name = "stellar",
      c.root(c.node({
        c.run(function() end),
      })),
    })

    it("generates valid Bash completion script", function()
      local script = comp_mod.completion_script(app, "bash")
      assert.truthy(script:find("__clingy_7374656c6c6172_complete%(%)"), "defines bash completion function")
      assert.truthy(script:find("%-%-__clingy%-complete bash"), "invokes hidden entrypoint with bash")
      assert.truthy(script:find("_init_completion %-n =:"), "keeps colon forms in one word")
      assert.truthy(script:find("complete %-o default %-F __clingy_7374656c6c6172_complete 'stellar'"), "registers complete command")
    end)

    it("generates valid Zsh completion script", function()
      local script = comp_mod.completion_script(app, "zsh")
      assert.truthy(script:find("#compdef stellar"), "defines #compdef header")
      assert.truthy(script:find("%-%-__clingy%-complete zsh"), "invokes hidden entrypoint with zsh")
      assert.truthy(script:find("compadd %-d descriptions"), "keeps values separate from descriptions")
      assert.truthy(script:find("compdef _clingy_7374656c6c6172 'stellar'"), "registers completion function")
    end)

    it("generates valid Fish completion script", function()
      local script = comp_mod.completion_script(app, "fish")
      assert.truthy(script:find("function __clingy_7374656c6c6172_complete"), "defines fish function")
      assert.truthy(script:find("%-%-__clingy%-complete fish"), "invokes hidden entrypoint with fish")
      assert.truthy(script:find('fish %$cmd "$current" %-%-cword=%$cword'), "passes the active token, including an empty trailing token")
      assert.truthy(script:find("__fish_complete_path"), "handles filesystem directives")
      assert.truthy(script:find("complete %-c 'stellar' %-f %-a '%(__clingy_7374656c6c6172_complete%)'"), "registers fish completer")
    end)

    it("generates valid PowerShell completion script", function()
      local script = comp_mod.completion_script(app, "powershell")
      assert.truthy(script:find("Register%-ArgumentCompleter %-Native %-CommandName 'stellar'"), "registers argument completer")
      assert.truthy(script:find("%-%-__clingy%-complete powershell"), "invokes hidden entrypoint with powershell")
    end)

    it("supports alias 'pwsh' as equivalent to powershell", function()
      local script = comp_mod.completion_script(app, "pwsh")
      assert.truthy(script:find("Register%-ArgumentCompleter %-Native %-CommandName 'stellar'"))
    end)

    it("raises an error for unsupported shell name", function()
      assert.has_error(function()
        comp_mod.completion_script(app, "csh")
      end, "Unsupported completion shell 'csh'")
    end)
  end)

  describe("Response Rendering: Bash Backend", function()
    it("renders plain candidate values without descriptions", function()
      local resp = response.create()
      resp:add("deploy", "Deploy the service")
      resp:add("status", "Show current status")

      local out = backends.bash.render(resp)
      local lines = {}
      for line in out:gmatch("[^\n]+") do table.insert(lines, line) end

      assert.equal(#lines, 3)
      assert.equal(lines[1], "V\t2")
      assert.equal(lines[2], "C\tdeploy")
      assert.equal(lines[3], "C\tstatus")
      assert.is_nil(out:find("Deploy the service"), "bash omits descriptions")
    end)

    it("emits directive header when directives are present", function()
      local resp = response.create()
      resp:add_directive(response.DIRECTIVE.FILENAMES)
      resp:add_directive(response.DIRECTIVE.NO_SPACE)
      resp:add("main.lua")

      local out = backends.bash.render(resp)
      assert.truthy(out:find("D\tfilenames,nospace\t%-\t%-\t%-", 1), "emits typed directive record")
      assert.truthy(out:find("C\tmain.lua", 1, true))
    end)

    it("returns empty string when no candidates or directives exist", function()
      local resp = response.create()
      local out = backends.bash.render(resp)
      assert.equal(out, "V\t2")
    end)
  end)

  describe("Response Rendering: Zsh Backend", function()
    it("keeps colons in values separate from descriptions", function()
      local resp = response.create()
      resp:add("argument:sad pepe", "Kind: user")
      resp:add("raw")

      local out = backends.zsh.render(resp)
      assert.truthy(out:find("C\targument:sad pepe\tKind: user", 1, true))
      assert.truthy(out:find("C\traw\t", 1, true))
    end)

    it("emits directive header for filenames and directories in zsh", function()
      local resp = response.create()
      resp:add_directive(response.DIRECTIVE.DIRECTORIES)
      local out = backends.zsh.render(resp)
      assert.truthy(out:find("D\tdirnames\t-\t-\t-", 1, true))
    end)
  end)

  describe("Response Rendering: Fish Backend", function()
    it("renders tab-separated value and description", function()
      local resp = response.create()
      resp:add("start", "Start the daemon")
      resp:add("stop")

      local out = backends.fish.render(resp)
      assert.truthy(out:find("C\tstart\tStart the daemon", 1, true), "separates value and description by tab")
      assert.truthy(out:find("C\tstop\t", 1, true), "includes an explicit empty description")
    end)
  end)

  describe("Response Rendering: PowerShell Backend", function()
    it("renders tab-separated value and description for PowerShell parsing", function()
      local resp = response.create()
      resp:add("init", "Initialize workspace")
      local out = backends.powershell.render(resp)
      assert.equal(out, "V\t2\nC\tinit\tInitialize workspace")
    end)
  end)

  it("serializes file filters and replacement prefixes", function()
    local resp = c.file({ extensions = { "luax", ".lua", "*.lua" } }):resolve({ prefix = "" })
    resp.replace_prefix = "argument:"
    local out = backends.bash.render(resp)
    assert.truthy(out:find("D\tfilenames\tfile\targument:\tlua,luax", 1, true))
  end)

  it("serializes nofiles so shell fallbacks can be disabled", function()
    local out = backends.bash.render(c.none():resolve({ prefix = "" }))
    assert.truthy(out:find("D\tnofiles\t-\t-\t-", 1, true))
  end)

end)
