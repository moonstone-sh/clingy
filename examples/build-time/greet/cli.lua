-- The declaration. Only `clingy.build` and `c.create` load it; a built CLI
-- never does.
local c = require("clingy")
local v = require("valua")
local handlers = require("greet.handlers")

return {
  name = "greet",
  root = c.node({
    c.flag({ key = "shout", aliases = { "-s", "--shout" } }),
    c.option({ key = "greeting", aliases = { "-g", "--greeting" },
      value = { schema = v.string(), attached = { "=" }, detached = true } }),
    c.option({ key = "times", aliases = { "-n", "--times" },
      value = { schema = v.pipe(v.integer(), v.min_value(1)), attached = { "=" }, detached = true } }),
    c.arg({ key = "name", schema = v.string() }),
    c.run(handlers.greet),
  }),
}
