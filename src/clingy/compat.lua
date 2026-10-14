-- Lua-version differences Clingy depends on, in one place.
--
-- One untagged module on purpose: both helpers are short, and the exit-status
-- shape cannot be fixed per Moonstone flavor, because LuaJIT returns the 5.1
-- shape by default and the 5.2 shape when built with LUAJIT_ENABLE_LUA52COMPAT.
-- See docs/PLATFORM_SUPPORT.md, "Lua flavors".

local compat = {}

local is_windows = package.config:sub(1, 1) == "\\"

---The integer value of `n`, or nil when `n` is not a finite number with an
---integral value. Same contract as `math.tointeger` on Lua 5.3+.
---@param n any
---@return integer|nil
compat.to_integer = math.tointeger or function(n)
  if type(n) == "number" and n == n and n > -math.huge and n < math.huge and n % 1 == 0 then
    return n
  end
  return nil
end

---Normalize what `os.execute` or a `io.popen` handle's `close()` returned into
---a shell-style exit code (0 success, 128+N for signal N).
---
---* Lua 5.2+ (and LuaJIT with 5.2 compatibility): `true|nil, "exit"|"signal", code`.
---* Lua 5.1 and LuaJIT: `os.execute` returns the C `system()` result, a raw
---  wait status on POSIX (exit 3 is 768). `close()` on a popen handle returns
---  `true` whatever the child did, so a status is not available there and 0 is
---  reported.
---@param ok boolean|number|nil
---@param how string|nil
---@param code number|nil
---@return integer
function compat.exit_status(ok, how, code)
  if type(ok) == "number" then
    if is_windows then return ok end
    if ok < 0 then return 1 end
    if ok % 256 == 0 then return math.floor(ok / 256) end
    return 128 + ok % 128
  end
  if ok then return 0 end
  if how == "signal" and type(code) == "number" then return 128 + code end
  if type(code) == "number" then return code end
  return 1
end

return compat
