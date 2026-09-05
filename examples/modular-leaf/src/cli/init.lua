local c = require("clingy")
local v = require("valua")
local shared_output = require("cli.shared.output")

return c.node({
    shared_output,
    c.arg("dirname", v.string()),
    c.flag("-f", "--force"),

    c.run(function(ctx)
        ctx:log("info", string.format("Initializing %s (force=%s)", ctx.args.dirname, tostring(ctx.args.force)))
        return { dir = ctx.args.dirname, force = ctx.args.force }
    end),
}, {
    description = "Initialize a new project structure",
})
