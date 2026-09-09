local c = require("clingy")
local v = require("valua")

local app
app = c.create({
  name = "clingy-example",
  version = "0.3.0",
  c.root(c.node({
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
  })),
})

os.exit(app:run(arg) or 0)
