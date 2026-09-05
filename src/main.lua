local c = require("clingy")
local v = require("valua")

local Profile = v.describe(
  v.picklist({
    "development",
    "production",
    "test",
  }),
  "Project profile"
)

local Define = v.describe(
  v.string(),
  "Build-time definition"
)

local CLI = c.create({
  name = "meteorite",
  version = "0.1.0",

  c.root(c.node({
    c.inherit(
      c.interspersed(),
      c.short_clusters(),

      c.flag("-v", "--verbose"),
      c.flag("-q", "--quiet")
    ),

    init = c.node({
      c.inherit(
        c.flag("--json")
      ),

      c.arg("profile", Profile),

      instant = c.node({
        c.flag("-n", "--now"),

        c.signals({
          interrupt = function(ctx)
            return ctx:confirm("Abort initialization?")
          end,

          terminate = function()
            return c.signal.shutdown()
          end,
        }),

        c.run(function(ctx)
          ctx:log("info", "Initialized Meteorite project instantly")
          ctx:result({
            status = "initialized",
            profile = ctx.args.profile,
            instant = ctx.args.now,
          })
        end),
      }, {
        description = "Instantaneous initialization",
      }),
    }, {
      description = "Initialize a Meteorite project",
    }),

    build = c.node({
      c.repeated(
        c.option("-D", "--define", Define)
      ),

      c.run(function(ctx)
        ctx:milestone("Build started")
        ctx:result({
          status = "built",
          defines = ctx.args.define or {},
        })
      end),
    }, {
      description = "Build the Meteorite project",
    }),

    legacy = c.node({
      c.ordered(),

      c.flag("--prepare"),
      c.arg("source", v.string()),
      c.flag("--commit"),
      c.arg("destination", v.string()),

      c.run(function(ctx)
        ctx:result({
          status = "migrated",
          source = ctx.args.source,
          destination = ctx.args.destination,
        })
      end),
    }, {
      description = "Run legacy migration workflow",
    }),
  })),
})

local exit_code = CLI:run(arg)
os.exit(exit_code or 0)
