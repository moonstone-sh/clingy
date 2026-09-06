local c = require("clingy")

return c.group({
    c.flag("-q", "--quiet"),
    c.flag("--json"),
    c.complete(c.path(), c.option("--log-file")),
    c.complete(c.values({ "text", "json", "yaml" }), c.option("--format")),
})
