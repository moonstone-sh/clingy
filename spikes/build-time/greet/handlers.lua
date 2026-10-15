local M = {}
function M.greet(ctx)
  local name = ctx.args.shout and ctx.args.name:upper() or ctx.args.name
  ctx:log("info", string.format("%s, %s!", ctx.args.greeting or "Hello", name))
end
return M
