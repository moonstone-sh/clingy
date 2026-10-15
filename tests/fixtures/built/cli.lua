local c = require("clingy")
local v = require("valua")
local handlers = require("tests.fixtures.built.handlers")

return {
  name = "fixture",
  version = "1.2.3",
  root = c.node({
    c.inherit(c.flag({ key = "verbose", aliases = { "-v", "--verbose" } })),
    add = c.node({
      c.arg({ key = "kind", schema = v.picklist({ "file", "dir" }) }),
      c.option({ key = "tag", aliases = { "-t", "--tag" }, value = { schema = v.string() }, occurs = { min = 0, max = "many" } }),
      c.option({ key = "count", aliases = { "-n" }, value = { schema = handlers.even } }),
      c.option({ key = "owner", aliases = { "--owner" }, value = { schema = v.string() }, complete = c.dynamic(handlers.names) }),
      c.option({ key = "config", aliases = { "--config" }, value = { schema = v.string() }, complete = c.file({ extensions = { "toml" } }) }),
      c.run(handlers.add),
    }),
    run = c.node({
      c.arg({ key = "script", schema = v.string() }),
      c.passthrough("rest"),
      c.run(handlers.run),
    }),
  }),
}
