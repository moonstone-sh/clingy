local c = require("clingy")
local v = require("valua")

local app
app = c.create({
  name = "clingy-example",
  version = "0.4.0",
  root = c.node({
    chain = c.node({
      c.flag({ key = "ready", aliases = { "--first-flag-completed" } }),
      c.option({
        key = "config",
        aliases = { "--config" },
        complete = c.file({ extensions = { "luax" } }),
      }),
      c.arg({ key = "subject", form = c.sequence({
        c.literal({ text = "argument:" }),
        c.capture({
          key = "value",
          schema = v.string(),
          complete = c.values({ "thisgotcompletedtoo", "other:value", "sad pepe" }),
        }),
      }) }),
      c.arg({
        key = "path",
        schema = v.string(),
        complete = c.file({ extensions = { "luax" } }),
      }),
      c.run(function() end),
    }),
    greet = c.node({
      c.arg({ key = "name", schema = v.string() }),
      c.run(function(ctx)
        print("hello " .. ctx.args.name)
      end),
    }),
    completion = c.node({
      c.arg({ key = "shell", schema = v.picklist({ "bash", "zsh", "fish", "powershell" }) }),
      c.run(function(ctx)
        io.write(ctx.app:completion_script(ctx.args.shell, "clingy-example"), "\n")
      end),
    }),
  }),
})

os.exit(app:run(arg) or 0)
