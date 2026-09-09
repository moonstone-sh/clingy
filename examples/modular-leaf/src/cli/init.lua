local c = require("clingy")
local v = require("valua")
local shared_output = require("cli.shared.output")

return c.node({
    shared_output,
    c.arg({ key = "dirname", schema = v.string(), complete = c.directory() }),
    c.option({ key = "template", aliases = { "-t", "--template" }, complete = c.values({ "starter", "standard", "enterprise" }) }),
    c.flag({ key = "force", aliases = { "-f", "--force" } }),

    c.run(function(ctx)
        ctx:log("info", string.format("Initializing %s (template=%s, force=%s)",
            ctx.args.dirname, tostring(ctx.args.template or "starter"), tostring(ctx.args.force)))
        return { dir = ctx.args.dirname, template = ctx.args.template, force = ctx.args.force }
    end),
}, {
    description = "Initialize a new project structure",
})
