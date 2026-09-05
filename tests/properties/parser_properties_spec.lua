local harness = require("tests.harness")
local describe, it = harness.describe, harness.it
local assert = harness.assert

local c = require("clingy")
local v = require("valua")

describe("Parser Invariants & Property Tests (Section 48)", function()
  it("Property: Interspersed invariance across all permutation positions", function()
    local app = c.create({
      name = "copy",
      c.root(c.node({
        c.interspersed(),
        c.arg("src", v.string()),
        c.arg("dst", v.string()),
        c.flag("-f", "--force"),
        c.option("-m", "--mode", v.string()),
        c.run(function() end),
      })),
    })

    local permutations = {
      { "-f", "-m", "fast", "file1.txt", "file2.txt" },
      { "file1.txt", "-f", "-m", "fast", "file2.txt" },
      { "file1.txt", "-m", "fast", "file2.txt", "-f" },
      { "file1.txt", "file2.txt", "-f", "-m", "fast" },
      { "-m", "fast", "file1.txt", "-f", "file2.txt" },
      { "--mode=fast", "file1.txt", "file2.txt", "--force" },
    }

    for idx, argv in ipairs(permutations) do
      local res = app:parse(argv)
      assert.equal(res.args.src, "file1.txt", "Permutation " .. idx .. " failed src")
      assert.equal(res.args.dst, "file2.txt", "Permutation " .. idx .. " failed dst")
      assert.equal(res.args.force, true, "Permutation " .. idx .. " failed force")
      assert.equal(res.args.mode, "fast", "Permutation " .. idx .. " failed mode")
    end
  end)

  it("Property: Cluster equivalence (-xfv == -x -f -v)", function()
    local app = c.create({
      name = "tar",
      c.root(c.node({
        c.short_clusters(),
        c.flag("-x", "--extract"),
        c.flag("-f", "--force"),
        c.flag("-v", "--verbose"),
        c.arg("archive", v.string()),
        c.run(function() end),
      })),
    })

    local clustered = app:parse({ "-xfv", "bundle.tar" })
    local unclustered = app:parse({ "-x", "-f", "-v", "bundle.tar" })
    local mixed = app:parse({ "-xf", "-v", "bundle.tar" })

    assert.equal(clustered.args.extract, true)
    assert.equal(clustered.args.force, true)
    assert.equal(clustered.args.verbose, true)
    assert.equal(clustered.args.archive, "bundle.tar")

    assert.equal(unclustered.args.extract, true)
    assert.equal(unclustered.args.force, true)
    assert.equal(unclustered.args.verbose, true)
    assert.equal(unclustered.args.archive, "bundle.tar")

    assert.equal(mixed.args.extract, true)
    assert.equal(mixed.args.force, true)
    assert.equal(mixed.args.verbose, true)
    assert.equal(mixed.args.archive, "bundle.tar")
  end)

  it("Property: Locality vs Inheritance boundary transition invariance", function()
    local app = c.create({
      name = "boundary-test",
      c.root(c.node({
        c.inherit(
          c.flag("-g", "--global")
        ),
        c.flag("-r", "--root-local"),

        child = c.node({
          c.inherit(
            c.flag("-c", "--child-inherited")
          ),
          c.flag("-l", "--child-local"),

          grandchild = c.node({
            c.run(function() end),
          }),
        }),
      })),
    })

    -- On grandchild: --global and --child-inherited must work
    local res = app:parse({ "child", "grandchild", "--global", "--child-inherited" })
    assert.equal(res.args.global, true)
    assert.equal(res.args.child_inherited, true)

    -- --root-local and --child-local must fail on grandchild
    assert.has_error(function()
      app:parse({ "child", "grandchild", "--root-local" })
    end, "Unknown option")

    assert.has_error(function()
      app:parse({ "child", "grandchild", "--child-local" })
    end, "Unknown option")
  end)

  it("Property: Router determinism over 500 random cyclic parsing runs", function()
    local app = c.create({
      name = "router-determinism",
      c.root(c.node({
        c.inherit(c.flag("-v", "--verbose")),
        c.flag("-d", "--debug"),

        alpha = c.node({
          c.arg("target", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
        beta = c.node({
          c.option("-o", "--out", v.string()),
          c.run(function(ctx) return ctx.args end),
        }),
      })),
    })

    for i = 1, 500 do
      local run_type = i % 2
      if run_type == 0 then
        local res = app:parse({ "alpha", "target_" .. i, "-v" })
        assert.equal(res.args.target, "target_" .. i)
        assert.equal(res.args.verbose, true)
      else
        local res = app:parse({ "-v", "beta", "-o", "file_" .. i .. ".txt" })
        assert.equal(res.args.out, "file_" .. i .. ".txt")
        assert.equal(res.args.verbose, true)
      end
    end
  end)
end)
