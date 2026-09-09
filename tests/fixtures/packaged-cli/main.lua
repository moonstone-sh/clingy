local c = require("clingy")
local v = require("valua")

local app = c.create({
  name = "clingy-example",
  version = "0.3.0",
  c.root(c.node({
    greet = c.node({
      c.arg({ key = "name", schema = v.string() }),
      c.run(function(ctx)
        print("hello " .. ctx.args.name)
      end),
    }),
  })),
})

os.exit(app:run(arg) or 0)
