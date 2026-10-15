-- Writes plain Lua data as a Lua chunk. Tables reached more than once are
-- created first and filled afterwards, so sharing and cycles survive; every
-- other table is a constructor. Keys are sorted, so the same data always
-- produces the same text.
--
-- `expression(value)` may return Lua source for a value that is not data (a
-- function or schema). Any other function, userdata, thread, table with a
-- metatable, or non-scalar key fails with the path where it was found.

local M = {}

local function compare_keys(a, b)
  local ta, tb = type(a), type(b)
  if ta ~= tb then return ta < tb end
  if ta == "number" or ta == "string" then return a < b end
  return tostring(a) < tostring(b)
end

local function sorted_keys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys, compare_keys)
  return keys
end
M.sorted_keys = sorted_keys

local function number(v)
  if v ~= v then return "(0/0)" end
  if v == math.huge then return "math.huge" end
  if v == -math.huge then return "-math.huge" end
  if math.type then
    if math.type(v) == "integer" then return string.format("%d", v) end
    local text = string.format("%.17g", v)
    if not text:find("[%.eEn]") then text = text .. ".0" end
    return text
  end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then return string.format("%d", v) end
  return string.format("%.17g", v)
end

local function is_identifier(k)
  return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil and not ({
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true, ["elseif"] = true, ["end"] = true,
    ["false"] = true, ["for"] = true, ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
    ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true, ["return"] = true,
    ["then"] = true, ["true"] = true, ["until"] = true, ["while"] = true,
  })[k]
end

M.is_identifier = is_identifier

---@param root any The value to write.
---@param opts { expression: fun(value: any, path: string): string?, skip?: fun(key: any, parent: table): boolean, shared?: string }
---@return string prelude Statements that create and fill shared tables, in a local named `opts.shared` (default "T").
---@return string value An expression for `root`.
function M.write(root, opts)
  local expression = opts.expression
  local skip = opts.skip or function() return false end
  local T = opts.shared or "T"
  local external, count, order = {}, {}, {}

  local function scan(v, path)
    local tv = type(v)
    if tv ~= "table" and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then return end
    if external[v] ~= nil then return end
    local expr = expression(v, path)
    if expr then external[v] = expr; return end
    if tv ~= "table" then
      error(("%s at %s is not data and has no module reference"):format(tv, path), 0)
    end
    if getmetatable(v) ~= nil then
      error(("table with a metatable at %s is not data and has no module reference"):format(path), 0)
    end
    count[v] = (count[v] or 0) + 1
    if count[v] > 1 then return end
    order[#order + 1] = v
    for _, k in ipairs(sorted_keys(v)) do
      if not skip(k, v) then
        local tk = type(k)
        if tk ~= "string" and tk ~= "number" and tk ~= "boolean" then
          error(("%s key at %s cannot be written as data"):format(tk, path), 0)
        end
        scan(v[k], path .. (is_identifier(k) and ("." .. k) or ("[" .. tostring(k) .. "]")))
      end
    end
  end
  scan(root, "root")

  local id, shared = {}, 0
  for _, t in ipairs(order) do
    if count[t] > 1 then shared = shared + 1; id[t] = shared end
  end

  local WIDTH = 100
  local value
  local function key(k)
    if is_identifier(k) then return k end
    return "[" .. value(k, 0) .. "]"
  end
  -- Short constructors stay on one line; longer ones get one field per line.
  function value(v, depth)
    local tv = type(v)
    if tv == "string" then return string.format("%q", v) end
    if tv == "number" then return number(v) end
    if tv == "boolean" or tv == "nil" then return tostring(v) end
    if external[v] then return external[v] end
    if id[v] then return T .. "[" .. id[v] .. "]" end
    local parts, n = {}, #v
    for i = 1, n do
      if skip(i, v) or v[i] == nil then n = i - 1; break end
      parts[i] = value(v[i], depth + 1)
    end
    for _, k in ipairs(sorted_keys(v)) do
      local positional = type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)
      if not positional and not skip(k, v) then parts[#parts + 1] = key(k) .. " = " .. value(v[k], depth + 1) end
    end
    if #parts == 0 then return "{}" end
    local inline = "{ " .. table.concat(parts, ", ") .. " }"
    if #inline + depth * 2 <= WIDTH and not inline:find("\n") then return inline end
    local pad = string.rep("  ", depth + 1)
    return "{\n" .. pad .. table.concat(parts, ",\n" .. pad) .. ",\n" .. string.rep("  ", depth) .. "}"
  end

  local lines = {}
  if shared > 0 then
    lines[#lines + 1] = "local " .. T .. " = {}"
    lines[#lines + 1] = "for i = 1, " .. shared .. " do " .. T .. "[i] = {} end"
    for _, t in ipairs(order) do
      if id[t] then
        for _, k in ipairs(sorted_keys(t)) do
          if not skip(k, t) then
            local field = is_identifier(k) and ("." .. k) or ("[" .. value(k, 0) .. "]")
            lines[#lines + 1] = T .. "[" .. id[t] .. "]" .. field .. " = " .. value(t[k], 0)
          end
        end
      end
    end
  end
  return table.concat(lines, "\n"), value(root, 0)
end

return M
