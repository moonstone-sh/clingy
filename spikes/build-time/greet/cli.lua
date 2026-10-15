-- The declaration. Functions and schemas live in runtime modules, so the
-- built graph can reference them by module path.
local c = require("clingy")
local handlers = require("greet.handlers")
local schemas = require("greet.schemas")
return {
  name = "greet",
  root = c.node({
    c.flag({ key = "shout", aliases = { "-s", "--shout" } }),
    c.option({ key = "greeting", aliases = { "-g", "--greeting" },
      value = { schema = schemas.greeting, attached = { "=" }, detached = true } }),
    c.option({ key = "times", aliases = { "-n", "--times" },
      value = { schema = schemas.times, attached = { "=" }, detached = true } }),
    c.arg({ key = "name", schema = schemas.name }),
    c.run(handlers.greet),
  }),
}
