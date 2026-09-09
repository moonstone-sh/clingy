local c = require("clingy")

return c.group({
    c.flag({ key = "quiet", aliases = { "-q", "--quiet" } }),
    c.flag({ key = "json", aliases = { "--json" } }),
    c.complete(c.path(), c.option({ key = "log_file", aliases = { "--log-file" } })),
    c.complete(c.values({ "text", "json", "yaml" }), c.option({ key = "format", aliases = { "--format" } })),
})
