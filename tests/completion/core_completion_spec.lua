--[[
  tests/completion/core_completion_spec.lua
  Core completion engine tests: routing traversal, visibility scope isolation,
  cardinality suppression, grammar modes, passthrough, and cursor position semantics.
]]

local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Core Shell Completion Engine", function()

  describe("Subcommand Completion at Root and Nested Segments", function()
    local app = c.create({
      name = "k8s",
      c.root(c.node({
        cluster = c.node({
          create = c.node({
            c.run(function() end),
          }, { description = "Create a cluster" }),
          delete = c.node({
            c.run(function() end),
          }, { description = "Delete a cluster" }),
          node = c.node({
            drain = c.node({
              c.run(function() end),
            }, { description = "Drain a node" }),
            cordon = c.node({
              c.run(function() end),
            }, { description = "Cordon a node" }),
          }, { description = "Node management" }),
        }, { description = "Cluster operations" }),

        config = c.node({
          view = c.node({
            c.run(function() end),
          }, { description = "View config" }),
        }, { description = "Configuration" }),
      })),
    })

    it("completes subcommands at root with empty prefix (k8s <TAB>)", function()
      local resp = app:complete({ "k8s", "" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = cand.description end
      assert.truthy(vals["cluster"], "suggests cluster at root")
      assert.truthy(vals["config"], "suggests config at root")
      assert.equal(vals["cluster"], "Cluster operations")
    end)

    it("filters root subcommands by prefix (k8s cl<TAB>)", function()
      local resp = app:complete({ "k8s", "cl" })
      assert.equal(#resp.candidates, 1)
      assert.equal(resp.candidates[1].value, "cluster")
    end)

    it("navigates down one segment and completes child commands (k8s cluster <TAB>)", function()
      local resp = app:complete({ "k8s", "cluster", "" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["create"], "suggests create")
      assert.truthy(vals["delete"], "suggests delete")
      assert.truthy(vals["node"], "suggests node")
      assert.falsy(vals["config"], "does not suggest sibling root commands")
    end)

    it("navigates deep multi-level nested segments (k8s cluster node <TAB>)", function()
      local resp = app:complete({ "k8s", "cluster", "node", "" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["drain"], "suggests drain")
      assert.truthy(vals["cordon"], "suggests cordon")
      assert.falsy(vals["create"], "does not suggest parent commands")
    end)

    it("filters deep nested commands by prefix (k8s cluster node dr<TAB>)", function()
      local resp = app:complete({ "k8s", "cluster", "node", "dr" })
      assert.equal(#resp.candidates, 1)
      assert.equal(resp.candidates[1].value, "drain")
      assert.equal(resp.candidates[1].description, "Drain a node")
    end)
  end)

  describe("Visible Options & Flags: Local vs Inherited Scope Isolation", function()
    local app = c.create({
      name = "sys",
      c.root(c.node({
        c.inherit(c.flag("-g", "--global", { description = "Global verbosity" })),
        c.flag("-r", "--root-only", { description = "Root only flag" }),

        service = c.node({
          c.inherit(c.option("-n", "--namespace", v.string())),
          c.flag("-s", "--service-flag"),

          start = c.node({
            c.flag("-f", "--force"),
            c.run(function() end),
          }),

          stop = c.node({
            c.flag("-k", "--kill"),
            c.run(function() end),
          }),
        }),

        database = c.node({
          c.flag("-d", "--db-flag"),
          c.run(function() end),
        }),
      })),
    })

    it("root command sees root options and inherited flags", function()
      local resp = app:complete({ "sys", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-g"])
      assert.truthy(vals["--global"])
      assert.truthy(vals["-r"])
      assert.truthy(vals["--root-only"])
      assert.falsy(vals["-s"], "does not see child service flag")
      assert.falsy(vals["-d"], "does not see child database flag")
    end)

    it("subcommand inherits ancestor inherited flags but NOT non-inherited options", function()
      local resp = app:complete({ "sys", "service", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-g"], "sees inherited global flag")
      assert.truthy(vals["--global"])
      assert.truthy(vals["-n"], "sees service namespace option")
      assert.truthy(vals["-s"], "sees local service flag")
      assert.falsy(vals["-r"], "does NOT see uninherited root-only flag")
      assert.falsy(vals["-d"], "does NOT see sibling database flag")
    end)

    it("leaf command inherits from both root and intermediate ancestor", function()
      local resp = app:complete({ "sys", "service", "start", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-g"], "sees root inherited flag")
      assert.truthy(vals["-n"], "sees intermediate service inherited option")
      assert.truthy(vals["-f"], "sees local start flag")
      assert.falsy(vals["-k"], "does NOT see sibling stop flag")
      assert.falsy(vals["-s"], "does NOT see uninherited intermediate service flag")
    end)

    it("isolates sibling command scopes completely", function()
      local resp = app:complete({ "sys", "database", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-d"], "sees database flag")
      assert.truthy(vals["-g"], "sees root inherited flag")
      assert.falsy(vals["-n"], "isolated from service options")
      assert.falsy(vals["-s"], "isolated from service flags")
    end)
  end)

  describe("Cardinality Suppression (Consumed Non-Repeatable vs Repeatable Options)", function()
    local app = c.create({
      name = "card_test",
      c.root(c.node({
        c.flag("-v", "--verbose"),
        c.option("-c", "--config", v.string()),
        c.repeated(c.option("-D", "--define", v.string())),
        c.repeated(c.flag("-t", "--trace")),
        c.run(function() end),
      })),
    })

    it("suggests all flags and options before consumption", function()
      local resp = app:complete({ "card_test", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-v"])
      assert.truthy(vals["--verbose"])
      assert.truthy(vals["-c"])
      assert.truthy(vals["--config"])
      assert.truthy(vals["-D"])
      assert.truthy(vals["--define"])
      assert.truthy(vals["-t"])
      assert.truthy(vals["--trace"])
    end)

    it("suppresses non-repeatable flag once consumed (short and long aliases)", function()
      local resp = app:complete({ "card_test", "--verbose", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.falsy(vals["--verbose"], "suppresses consumed --verbose")
      assert.falsy(vals["-v"], "suppresses alias -v")
      assert.truthy(vals["--config"], "keeps unconsumed options")
      assert.truthy(vals["--define"], "keeps repeatable options")
    end)

    it("suppresses non-repeatable option once consumed with value", function()
      local resp = app:complete({ "card_test", "--config", "app.json", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.falsy(vals["--config"], "suppresses consumed --config")
      assert.falsy(vals["-c"], "suppresses alias -c")
      assert.truthy(vals["--verbose"], "keeps unconsumed flags")
      assert.truthy(vals["--define"], "keeps repeatable options")
    end)

    it("suppresses non-repeatable option consumed with inline form (--config=app.json)", function()
      local resp = app:complete({ "card_test", "--config=app.json", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.falsy(vals["--config"], "suppresses consumed inline --config")
      assert.falsy(vals["-c"], "suppresses alias -c")
    end)

    it("retains repeatable options and flags even after consumption", function()
      local resp = app:complete({ "card_test", "-D", "KEY1=VAL1", "--trace", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["-D"], "repeatable option remains")
      assert.truthy(vals["--define"], "repeatable option long form remains")
      assert.truthy(vals["-t"], "repeatable flag remains")
      assert.truthy(vals["--trace"], "repeatable flag long form remains")
      assert.falsy(vals["--trace_not_present"])
    end)
  end)

  describe("Grammar Modes Completion (Interspersed, Leading, Ordered)", function()
    -- 1. Interspersed Mode
    it("interspersed mode allows option completion before and after positional arguments", function()
      local app = c.create({
        name = "inter_test",
        c.root(c.node({
          c.interspersed(),
          c.arg("source", v.string()),
          c.arg("target", v.string()),
          c.flag("-f", "--force"),
          c.option("-m", "--mode", v.string()),
          c.run(function() end),
        })),
      })

      -- Before positional
      local resp1 = app:complete({ "inter_test", "-" })
      local vals1 = {}
      for _, cand in ipairs(resp1.candidates) do vals1[cand.value] = true end
      assert.truthy(vals1["--force"])
      assert.truthy(vals1["--mode"])

      -- After 1 positional
      local resp2 = app:complete({ "inter_test", "file1.txt", "-" })
      local vals2 = {}
      for _, cand in ipairs(resp2.candidates) do vals2[cand.value] = true end
      assert.truthy(vals2["--force"])
      assert.truthy(vals2["--mode"])

      -- After all positionals
      local resp3 = app:complete({ "inter_test", "file1.txt", "file2.txt", "-" })
      local vals3 = {}
      for _, cand in ipairs(resp3.candidates) do vals3[cand.value] = true end
      assert.truthy(vals3["--force"])
      assert.truthy(vals3["--mode"])
    end)

    -- 2. Leading Mode
    it("leading mode suppresses option completion once positional consumption begins", function()
      local app = c.create({
        name = "lead_test",
        c.root(c.node({
          c.leading(),
          c.arg("file", v.string()),
          c.flag("-a", "--all"),
          c.option("-o", "--output", v.string()),
          c.run(function() end),
        })),
      })

      -- Before positional: options permitted
      local resp1 = app:complete({ "lead_test", "-" })
      assert.truthy(#resp1.candidates > 0, "options available before positionals in leading mode")

      -- After positional: options prohibited!
      local resp2 = app:complete({ "lead_test", "input.txt", "-" })
      assert.equal(#resp2.candidates, 0, "no options suggested after positional in leading mode")
    end)

    -- 3. Ordered Mode
    it("ordered mode enforces completion according to declared sequence", function()
      local app = c.create({
        name = "ord_test",
        c.root(c.node({
          c.ordered(),
          c.flag("--step-one"),
          c.flag("--step-two"),
          c.flag("--step-three"),
          c.run(function() end),
        })),
      })

      -- Initially: all steps available in order
      local resp1 = app:complete({ "ord_test", "--step" })
      assert.equal(#resp1.candidates, 3)

      -- After --step-two is provided: --step-one is in the past; only --step-three remains
      local resp2 = app:complete({ "ord_test", "--step-two", "--step" })
      assert.equal(#resp2.candidates, 1)
      assert.equal(resp2.candidates[1].value, "--step-three")
    end)
  end)

  describe("Passthrough Grammar Completion Boundary", function()
    local app = c.create({
      name = "pt_test",
      c.root(c.node({
        c.passthrough("raw_args"),
        c.flag("-v", "--verbose"),
        c.option("-e", "--exec", v.string()),
        c.run(function() end),
      })),
    })

    it("options complete normally before '--'", function()
      local resp = app:complete({ "pt_test", "-" })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["--verbose"])
      assert.truthy(vals["--exec"])
    end)

    it("halts option completion after '--'", function()
      local resp = app:complete({ "pt_test", "--", "-" })
      assert.equal(#resp.candidates, 0, "no options completed after passthrough separator '--'")
    end)
  end)

  describe("Trailing Space Advancing vs In-Token Cursor Semantics", function()
    local app = c.create({
      name = "cursor_test",
      c.root(c.node({
        deploy = c.node({
          c.complete(c.values("eu-west", "us-east"), c.arg("region")),
          c.run(function() end),
        }),
        destroy = c.node({
          c.run(function() end),
        }),
      })),
    })

    it("cursor within token completes the token prefix (de<TAB>)", function()
      -- words = {"cursor_test", "de"}, cword = 2
      local resp = app:complete({
        words = { "cursor_test", "de" },
        cword = 2,
      })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["deploy"])
      assert.truthy(vals["destroy"])
    end)

    it("trailing space advances to next argument on target command (deploy <TAB>)", function()
      -- words = {"cursor_test", "deploy", ""}, cword = 3
      local resp = app:complete({
        words = { "cursor_test", "deploy", "" },
        cword = 3,
      })
      local vals = {}
      for _, cand in ipairs(resp.candidates) do vals[cand.value] = true end
      assert.truthy(vals["eu-west"], "advanced into deploy and completes its region positional")
      assert.truthy(vals["us-east"])
      assert.falsy(vals["destroy"], "does not suggest root sibling commands")
    end)
  end)

end)
