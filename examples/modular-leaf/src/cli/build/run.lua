local args = require("cli.build.args")

return function(ctx)
    local target = ctx:get(args.target)
    local release = ctx:get(args.release)
    local defines = ctx:get(args.defines) or {}

    ctx:log("info", string.format("Building target %s (release=%s)", target, tostring(release)))
    for i, def in ipairs(defines) do
        ctx:log("info", string.format("  [Define %d] %s", i, def))
    end
    return { target = target, release = release, defines = defines }
end
