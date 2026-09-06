local c = require("clingy")
local args = require("cli.build.args")
local run = require("cli.build.run")
local shared_output = require("cli.shared.output")

return c.node({
    shared_output,
    args.target,
    args.release,
    args.defines,
    args.out_dir,

    c.run(run),
}, {
    description = "Compile project build targets",
})
