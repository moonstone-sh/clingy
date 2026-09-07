local h = require("tests.harness")
local c = require("clingy")
local v = require("valua")

local describe, it = h.describe, h.it
local assert = h.assert

describe("Named declaration result keys and attached option spellings", function()
  it("uses explicit keys for flags and options without changing legacy key derivation", function()
    local explicit_flag = c.flag("dry_run", "--dry-run", "-n")
    local legacy_flag = c.flag("-n", "--dry-run")
    local schema = v.integer()
    local explicit_option = c.option("job_count", "--jobs", "-j", schema)
    local legacy_option = c.option("-j", "--jobs", schema)

    assert.equal(explicit_flag.result_key, "dry_run")
    assert.same(explicit_flag.names, { "--dry-run", "-n" })
    assert.equal(legacy_flag.result_key, "dry_run")
    assert.equal(explicit_option.result_key, "job_count")
    assert.same(explicit_option.names, { "--jobs", "-j" })
    assert.equal(explicit_option.schema, schema)
    assert.equal(legacy_option.result_key, "jobs")
    assert.equal(legacy_option.schema, schema)
  end)

  it("rejects empty, repeated, and misplaced declaration inputs", function()
    assert.has_error(function()
      c.flag("", "-f")
    end, "non-empty")
    assert.has_error(function()
      c.flag("first", "second", "-f")
    end, "only one explicit result_key")
    assert.has_error(function()
      c.option("config", "--config", v.string(), "-c")
    end, "schema must be the final")
  end)

  it("preserves alias-only schema placement while explicit-key schemas remain final", function()
    local early_schema = v.string()
    local legacy_early = c.option(early_schema, "--config", "-c")
    local legacy_string = c.option("--label", "legacy-string-schema")
    local explicit_string = c.option("config_key", "--config", "explicit-string-schema")

    assert.equal(legacy_early.result_key, "config")
    assert.equal(legacy_early.schema, early_schema)
    assert.equal(legacy_string.schema, "legacy-string-schema")
    assert.equal(explicit_string.result_key, "config_key")
    assert.equal(explicit_string.schema, "explicit-string-schema")
  end)

  local app = c.create({
    name = "named-declarations",
    c.root(c.node({
      c.separator({ "=", ":", " " }, c.label("destination", c.option("--output", "-o", v.string()))),
      c.label("dry_run", c.flag("--dry-run", "-n")),
      c.arg("target", v.string()),
      c.passthrough("forwarded"),
    })),
  })

  it("normalizes attached and detached option spellings across aliases", function()
    local spellings = {
      { "--output=dist", "target" },
      { "--output:dist", "target" },
      { "--output", "dist", "target" },
      { "-o=dist", "target" },
      { "-o:dist", "target" },
      { "-o", "dist", "target" },
    }

    for _, argv in ipairs(spellings) do
      local parsed = app:parse(argv)
      assert.equal(parsed.args.destination, "dist")
      assert.equal(parsed.args.target, "target")
      assert.equal(parsed.args.dry_run, false)
    end
  end)

  it("rejects attached values on flags, including colon form, and does not consume detached values", function()
    assert.has_error(function()
      app:parse({ "--dry-run=yes", "target" })
    end, "does not take a value")
    assert.has_error(function()
      app:parse({ "-n:no", "target" })
    end, "Unknown option")

    local parsed = app:parse({ "--dry-run", "target" })
    assert.equal(parsed.args.dry_run, true)
    assert.equal(parsed.args.target, "target")
  end)

  it("keeps -- as the boundary for option and flag recognition", function()
    local parsed = app:parse({ "--", "--output:ignored", "-n", "target" })

    assert.is_nil(parsed.args.destination)
    assert.equal(parsed.args.dry_run, false)
    assert.equal(parsed.args.target, "--output:ignored")
    assert.same(parsed.args.forwarded, { "-n", "target" })
  end)

  it("preserves exact aliases that contain colons", function()
    local colon_alias_app = c.create({
      name = "colon-alias",
      c.root(c.node({
        c.option("legacy_value", "--legacy:option", v.string()),
        c.flag("legacy_flag", "--legacy:flag"),
      })),
    })

    local parsed = colon_alias_app:parse({ "--legacy:option", "value", "--legacy:flag" })
    assert.equal(parsed.args.legacy_value, "value")
    assert.equal(parsed.args.legacy_flag, true)
  end)
  it("uses labels once, validates them, and applies declared separators", function()
    local flag = c.label("enabled", c.flag("--enabled"))
    assert.equal(flag.result_key, "enabled")
    assert.has_error(function() c.label("   ", c.flag("--bad")) end, "non%-whitespace")
    assert.has_error(function() c.label("again", flag) end, "exactly once")

    local only_equals = c.create({ name = "separators", c.root(c.node({
      c.separator("=", c.option("--value", v.string())),
    })) })
    assert.equal(only_equals:parse({ "--value=  kept  " }).args.value, "kept")
    assert.has_error(function() only_equals:parse({ "--value:value" }) end, "Unknown option")
    assert.has_error(function() only_equals:parse({ "--value", "value" }) end, "does not accept a detached value")

    local raw = c.create({ name = "raw", c.root(c.node({
      c.separator(":", c.option("--value", v.string()), { trim = false }),
    })) })
    assert.equal(raw:parse({ "--value:  kept  " }).args.value, "  kept  ")
  end)

  it("captures explicit tails with trimmed and complete forwarding", function()
    local trimmed = c.create({ name = "trimmed", c.root(c.node({
      c.tail("forwarded", "--", { c.forward("trimmed") }),
    })) })
    assert.same(trimmed:parse({ "--", "-x" }).args.forwarded, { "-x" })

    local complete = c.create({ name = "complete", c.root(c.node({
      c.tail("forwarded", "--", { c.forward("complete") }),
    })) })
    assert.same(complete:parse({ "--", "-x" }).args.forwarded, { "--", "-x" })

    local alias = c.create({ name = "alias", c.root(c.node({
      c["end"]("forwarded", "--", { c.forward("trimmed") }),
    })) })
    assert.same(alias:parse({ "--", "-x" }).args.forwarded, { "-x" })
  end)

end)
