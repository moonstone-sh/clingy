local c = require("clingy")
local v = require("valua")

return {
    target = c.arg("target", v.picklist({ "native", "wasm", "arm64" })),
    release = c.flag("-r", "--release"),
    defines = c.repeated(c.option("-D", "--define")),
}
