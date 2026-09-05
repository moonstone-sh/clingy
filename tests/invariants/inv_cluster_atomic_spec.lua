local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Invariant: Short-Cluster Transactional Atomicity (Section 3)", function()

  local function create_cluster_app()
    return c.create({
      name = "tar",
      c.root(c.node({
        c.inherit(
          c.flag("-v", "--verbose")
        ),
        c.flag("-r", "--root-local"),

        pack = c.node({
          c.short_clusters(),
          c.flag("-x", "--extract"),
          c.flag("-f", "--force"),
          c.flag("-z", "--gzip"),
          c.option("-j", "--threads", v.integer()),
          c.arg("archive", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })
  end

  it("successfully parses valid cluster with inherited and local flags (-xvz)", function()
    local app = create_cluster_app()
    local res = app:parse({ "pack", "-xvz", "bundle.tar.gz" })
    assert.truthy(res)
    assert.equal(res.args.extract, true)
    assert.equal(res.args.verbose, true)
    assert.equal(res.args.gzip, true)
    assert.equal(res.args.archive, "bundle.tar.gz")
  end)

  it("rejects cluster with unknown final member (-xfw) without partial mutation", function()
    local app = create_cluster_app()
    local ok, err = pcall(function()
      app:parse({ "pack", "-xfw", "bundle.tar" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Unknown option or flag '%-xfw'")
  end)

  it("rejects cluster with unknown middle member (-xwf) without partial mutation", function()
    local app = create_cluster_app()
    local ok, err = pcall(function()
      app:parse({ "pack", "-xwf", "bundle.tar" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Unknown option or flag '%-xwf'")
  end)

  it("rejects cluster containing value-taking option (-xvj) without partial mutation", function()
    local app = create_cluster_app()
    local ok, err = pcall(function()
      app:parse({ "pack", "-xvj", "bundle.tar" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Unknown option or flag '%-xvj'")
  end)

  it("rejects cluster referencing uninherited ancestor flag (-xvr) without partial mutation", function()
    local app = create_cluster_app()
    local ok, err = pcall(function()
      app:parse({ "pack", "-xvr", "bundle.tar" })
    end)
    assert.falsy(ok)
    assert.matches(tostring(err), "Unknown option or flag '%-xvr'")
  end)

  it("guarantees all-or-nothing semantic state across multiple failed parse attempts", function()
    local app = create_cluster_app()

    -- Attempt 1: bad cluster
    local ok1 = pcall(function() app:parse({ "pack", "-xvfz9", "archive.tar" }) end)
    assert.falsy(ok1)

    -- Attempt 2: valid cluster
    local res2 = app:parse({ "pack", "-xfz", "archive.tar" })
    assert.equal(res2.args.extract, true)
    assert.equal(res2.args.force, true)
    assert.equal(res2.args.gzip, true)
    assert.equal(res2.args.verbose, false)
  end)

end)
