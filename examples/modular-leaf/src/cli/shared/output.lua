local c = require("clingy")

return c.group({
    c.flag({ key = "quiet", aliases = { "-q", "--quiet" } }),
    c.flag({ key = "json", aliases = { "--json" } }),
    c.option({ key = "log_file", aliases = { "--log-file" }, complete = c.path() }),
    c.option({ key = "format", aliases = { "--format" }, complete = c.values({ "text", "json", "yaml" }) }),
})
