local c = require("clingy")
local v = require("valua")
local init_cmd = require("clingy.cli.init")

local app
app = c.create({
  name = "clingy",
  version = "0.5.0",
  description = "Deterministic Declarative CLI Engine for Lua",

  c.root(c.node({
    c.inherit({ c.flag({ key = "help", aliases = { "-h", "--help" } }) }),

    c.run(function(ctx)
      if ctx.args.help then
        io.stdout:write(app:help() .. "\n")
        return 0
      end
      io.stdout:write(app:help() .. "\n")
      return 0
    end),

    init = c.node({
      c.option({ key = "config", aliases = { "-c", "--config" }, value = { schema = v.string() } }),
      c.flag({ key = "yes", aliases = { "-y", "--yes" } }),

      c.run(function(ctx)
        if ctx.args.help then
          io.stdout:write(app:help("init") .. "\n")
          return 0
        end

        local res, err = init_cmd.run({
          config = ctx.args.config,
          yes = ctx.args.yes,
        })
        if not res then
          if err ~= "cancelled" then
            ctx:log("error", tostring(err and err.message or err))
            return 1
          end
          return 0
        end
        if res.changed then
          ctx:log("info", "Configured LuaLS for Clingy.")
        else
          ctx:log("info", "LuaLS is already configured for Clingy.")
        end
        return 0
      end),
    }, {
      description = "Initialize LuaLS IDE plugin configuration in .luarc.json",
    }),
  })),
})

local exit_code = app:run(arg)
os.exit(exit_code or 0)
