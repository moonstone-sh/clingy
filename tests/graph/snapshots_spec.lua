local harness = require("tests.harness")
local describe, it = harness.describe, harness.it
local assert = harness.assert

local c = require("clingy")
local v = require("valua")

describe("Command Graph IR - Deterministic Snapshots (Section 47)", function()
  it("snapshots a minimal command graph", function()
    local app = c.create({
      name = "simple",
      version = "1.0.0",
      description = "Simple CLI",
      c.root(c.node({
        c.flag("-v", "--verbose"),
        c.run(function() end),
      })),
    })

    local g = c.reflect(app)
    assert.equal(g.format, "clingy.command-graph.v0")
    assert.equal(g.name, "simple")
    assert.equal(g.version, "1.0.0")
    assert.equal(g.root, "root")

    local root = g.nodes["root"]
    assert.truthy(root ~= nil)
    assert.equal(root.id, "root")
    assert.equal(root.name, "root")
    assert.equal(#root.bindings, 1)

    local b_id = root.bindings[1]
    local b = g.bindings[b_id]
    assert.truthy(b ~= nil)
    assert.equal(b.owner, "root")
    assert.equal(b.kind, "flag")
    assert.equal(b.result_key, "verbose")
    assert.equal(b.visibility, "local")
    assert.equal(b.occurrence.min, 0)
    assert.equal(b.occurrence.max, 1)
  end)

  it("snapshots nested routing with local and inherited flags", function()
    local app = c.create({
      name = "nested",
      version = "0.1.0",
      c.root(c.node({
        c.inherit(
          c.flag("-q", "--quiet")
        ),
        c.flag("-l", "--local-root"),

        sub = c.node({
          c.flag("-s", "--sub-local"),
          c.arg("target", v.string()),

          leaf = c.node({
            c.flag("-n", "--now"),
            c.run(function() end),
          }),
        }),
      })),
    })

    local g = c.reflect(app)
    assert.truthy(g.nodes["root"] ~= nil)
    assert.truthy(g.nodes["root.sub"] ~= nil)
    assert.truthy(g.nodes["root.sub.leaf"] ~= nil)

    -- Check root bindings
    local quiet = g.bindings["root:quiet"]
    local local_root = g.bindings["root:local_root"]
    assert.equal(quiet.visibility, "descendants")
    assert.equal(local_root.visibility, "local")

    -- Check sub bindings
    local sub = g.nodes["root.sub"]
    assert.equal(sub.parent, "root")
    local sub_local = g.bindings["root.sub:sub_local"]
    local target = g.bindings["root.sub:target"]
    assert.equal(sub_local.owner, "root.sub")
    assert.equal(sub_local.visibility, "local")
    assert.equal(target.kind, "arg")
    assert.equal(target.position, 1)
    assert.equal(target.occurrence.min, 1)
    assert.equal(target.occurrence.max, 1)

    -- Check leaf node
    local leaf = g.nodes["root.sub.leaf"]
    assert.equal(leaf.parent, "root.sub")
    assert.equal(#leaf.child_order, 0)
  end)

  it("snapshots parser policies (interspersed, leading, ordered, short_clusters)", function()
    local app = c.create({
      name = "policies",
      c.root(c.node({
        c.inherit(
          c.interspersed(),
          c.short_clusters()
        ),

        lead = c.node({
          c.leading(),
        }),

        ord = c.node({
          c.ordered(),
          c.flag("--prepare"),
          c.arg("in", v.string()),
          c.flag("--commit"),
          c.arg("out", v.string()),
        }),
      })),
    })

    local g = c.reflect(app)
    local root = g.nodes["root"]
    assert.equal(root.parser_policy.ordering, "interspersed")
    assert.equal(root.parser_policy.ordering_inherited, true)
    assert.equal(root.parser_policy.short_clusters, true)
    assert.equal(root.parser_policy.short_clusters_inherited, true)

    local lead = g.nodes["root.lead"]
    assert.equal(lead.parser_policy.ordering, "leading")
    assert.equal(lead.parser_policy.ordering_inherited, false)

    local ord = g.nodes["root.ord"]
    assert.equal(ord.parser_policy.ordering, "ordered")
    assert.equal(#ord.declaration_order, 4)
    assert.equal(g.bindings[ord.declaration_order[1]].result_key, "prepare")
    assert.equal(g.bindings[ord.declaration_order[2]].result_key, "in")
    assert.equal(g.bindings[ord.declaration_order[3]].result_key, "commit")
    assert.equal(g.bindings[ord.declaration_order[4]].result_key, "out")
  end)

  it("snapshots repeated cardinality and passthrough declarations", function()
    local app = c.create({
      name = "advanced",
      c.root(c.node({
        build = c.node({
          c.repeated(
            c.option("-D", "--define", v.string())
          ),
          c.repeated(
            c.arg("sources", v.string())
          ),
          c.passthrough("forwarded"),
        }),
      })),
    })

    local g = c.reflect(app)
    local build_node = g.nodes["root.build"]
    assert.equal(build_node.passthrough_key, "forwarded")

    local define = g.bindings["root.build:define"]
    assert.equal(define.kind, "option")
    assert.equal(define.occurrence.min, 0)
    assert.equal(define.occurrence.max, nil)
    assert.equal(define.aggregate, "array")

    local sources = g.bindings["root.build:sources"]
    assert.equal(sources.kind, "arg")
    assert.equal(sources.occurrence.min, 1)
    assert.equal(sources.occurrence.max, nil)
    assert.equal(sources.aggregate, "array")

    local pt = g.bindings["root.build:--passthrough"]
    assert.equal(pt.kind, "passthrough")
    assert.equal(pt.result_key, "forwarded")
  end)
end)
