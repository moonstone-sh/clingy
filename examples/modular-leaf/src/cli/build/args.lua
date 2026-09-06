local c = require("clingy")
local v = require("valua")

return {
    target = c.arg("target", v.picklist({ "native", "wasm", "arm64" })),
    release = c.flag("-r", "--release"),
    defines = c.complete(c.values({ "OPT=3", "OPT=2", "DEBUG=1", "ARCH=arm64" }), c.repeated(c.option("-D", "--define"))),
    out_dir = c.complete(c.directory(), c.option("-o", "--out-dir")),
}
