local c = require("clingy")
local v = require("valua")
local shared_output = require("cli.shared.output")

return c.node({
    shared_output,
    c.complete(c.directory(), c.arg("dirname", v.string())),
    c.complete(c.values({ "starter", "standard", "enterprise" }), c.option("-t", "--template")),
    c.flag("-f", "--force"),

    c.run(function(ctx)
        ctx:log("info", string.format("Initializing %s (template=%s, force=%s)",
            ctx.args.dirname, tostring(ctx.args.template or "starter"), tostring(ctx.args.force)))
        return { dir = ctx.args.dirname, template = ctx.args.template, force = ctx.args.force }
    end),
}, {
    description = "Initialize a new project structure",
})
