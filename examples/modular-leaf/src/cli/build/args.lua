local c = require("clingy")
local v = require("valua")

return {
    target = c.arg({ key = "target", schema = v.picklist({ "native", "wasm", "arm64" }) }),
    release = c.flag({ key = "release", aliases = { "-r", "--release" } }),
    defines = c.option({ key = "define", aliases = { "-D", "--define" }, occurs = { min = 0, max = "many" }, complete = c.values({ "OPT=3", "OPT=2", "DEBUG=1", "ARCH=arm64" }) }),
    out_dir = c.option({ key = "out_dir", aliases = { "-o", "--out-dir" }, complete = c.directory() }),
}
