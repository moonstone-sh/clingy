package.path = "./src/?.lua;./src/?/init.lua;./?.lua;./?/init.lua;" .. package.path

local M = {}

M.passed = 0
M.failed = 0
M.errors = {}
M.current_suite = ""

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k, v in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function table_repr(tbl, depth)
  depth = depth or 0
  if depth > 3 then return "{...}" end
  if type(tbl) ~= "table" then
    if type(tbl) == "string" then return string.format("%q", tbl) end
    return tostring(tbl)
  end
  local parts = {}
  for k, v in pairs(tbl) do
    local key_str = type(k) == "string" and k or "[" .. tostring(k) .. "]"
    table.insert(parts, key_str .. " = " .. table_repr(v, depth + 1))
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

function M.describe(name, fn)
  local prev = M.current_suite
  M.current_suite = prev == "" and name or (prev .. " > " .. name)
  print("\n--- " .. M.current_suite .. " ---")
  local ok, err = pcall(fn)
  if not ok then
    M.failed = M.failed + 1
    local err_msg = "[" .. M.current_suite .. "] SUITE ERROR:\n  " .. tostring(err)
    table.insert(M.errors, err_msg)
    print("  ✗ SUITE ERROR: " .. tostring(err))
  end
  M.current_suite = prev
end

function M.it(name, fn)
  local ok, err = pcall(fn)
  if ok then
    M.passed = M.passed + 1
    print("  ✓ " .. name)
  else
    M.failed = M.failed + 1
    print("  ✗ " .. name)
    local full_name = "[" .. M.current_suite .. "] " .. name
    table.insert(M.errors, full_name .. ":\n    " .. tostring(err))
  end
end

M.assert = {}

function M.assert.equal(actual, expected, msg)
  if actual ~= expected then
    error(string.format("%sexpected %s, got %s",
      msg and (msg .. ": ") or "",
      table_repr(expected),
      table_repr(actual)), 2)
  end
end

function M.assert.not_equal(actual, expected, msg)
  if actual == expected then
    error(string.format("%sexpected values to differ, but both were %s",
      msg and (msg .. ": ") or "",
      table_repr(actual)), 2)
  end
end

function M.assert.truthy(cond, msg)
  if not cond then
    error((msg or "Expected truthy value, got " .. tostring(cond)), 2)
  end
end

function M.assert.falsy(cond, msg)
  if cond then
    error((msg or "Expected falsy value, got " .. tostring(cond)), 2)
  end
end

function M.assert.is_nil(val, msg)
  if val ~= nil then
    error((msg or "Expected nil, got " .. table_repr(val)), 2)
  end
end

function M.assert.not_nil(val, msg)
  if val == nil then
    error((msg or "Expected non-nil value, got nil"), 2)
  end
end

function M.assert.same(actual, expected, msg)
  if not deep_equal(actual, expected) then
    error(string.format("%stables do not match.\nExpected: %s\nActual:   %s",
      msg and (msg .. ": ") or "",
      table_repr(expected),
      table_repr(actual)), 2)
  end
end

function M.assert.matches(str, pattern, msg)
  if type(str) ~= "string" or not str:find(pattern) then
    error(string.format("%sexpected %q to match pattern %q",
      msg and (msg .. ": ") or "",
      tostring(str),
      pattern), 2)
  end
end

function M.assert.has_error(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then
    error((msg or "Expected function to raise error, but it succeeded"), 2)
  end
  if pattern and type(err) == "string" and not err:find(pattern, 1, true) and not err:match(pattern) then
    error(string.format("%sexpected error matching %q, got: %s",
      msg and (msg .. ": ") or "",
      pattern,
      tostring(err)), 2)
  end
  return err
end

function M.assert.no_error(fn, msg)
  local ok, res = pcall(fn)
  if not ok then
    error(string.format("%sexpected no error, but got: %s",
      msg and (msg .. ": ") or "",
      tostring(res)), 2)
  end
  return res
end

-- Export global shortcuts if running as a test script
_G.describe = _G.describe or M.describe
_G.it = _G.it or M.it
_G.assert_equal = _G.assert_equal or M.assert.equal
_G.assert_true = _G.assert_true or M.assert.truthy
_G.assert_false = _G.assert_false or M.assert.falsy

return M
