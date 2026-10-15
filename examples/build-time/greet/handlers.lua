-- Handlers live in a module so a built CLI can reference them by name.
-- Their context type comes from the generated args module; it is a LuaLS
-- annotation only, so nothing extra loads at run time.
local M = {}

---@param ctx greet.built.args.root.context
function M.greet(ctx)
  local name = ctx.args.name
  if ctx.args.shout then name = name:upper() end
  for _ = 1, ctx.args.times or 1 do
    ctx:log("info", string.format("%s, %s!", ctx.args.greeting or "Hello", name))
  end
end

return M
