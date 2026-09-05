local c = require("clingy")

return c.group({
    c.flag("-q", "--quiet"),
    c.flag("--json"),
    c.option("-o", "--output"),
})
