local h = require("tests.harness")

local describe, it = h.describe, h.it

-- Static bundlers (Quaver strict mode) need every module edge to be a literal
-- `require("name")`. `pcall(require, "x")` passes require as a value, which
-- they reject as a dynamic require; wrap optional loads in a closure instead.
local function lua_files()
  local files = {}
  local pipe = assert(io.popen('find src -name "*.lua" -type f | sort'))
  for path in pipe:lines() do files[#files + 1] = path end
  pipe:close()
  return files
end

-- Source with comments blanked out, keeping line breaks so numbers stay true.
local function code(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  text = text:gsub("%-%-%[(=*)%[.-%]%1%]", function(c) return (c:gsub("[^\n]", "")) end)
  return (text:gsub("%-%-[^\n]*", ""))
end

local function dynamic_requires(text)
  local found, init = {}, 1
  while true do
    local s, e = text:find("require", init, true)
    if not s then return found end
    init = e + 1
    local before, after = text:sub(s - 1, s - 1), text:sub(e + 1, e + 1)
    local word = before:match("[%w_%.:]") or after:match("[%w_]")
    local tail = text:sub(e + 1)
    local literal = tail:match("^%s*%(%s*[\"'][^\"'\n]+[\"']%s*%)") or tail:match("^%s*[\"'][^\"'\n]+[\"']")
    if not word and not literal then
      local _, newlines = text:sub(1, s):gsub("\n", "")
      found[#found + 1] = newlines + 1
    end
  end
end

describe("static module loading", function()
  it("finds require passed as a value", function()
    h.assert.same(dynamic_requires('local a = require("a")\nlocal ok = pcall(require, "b")\nx.require(y)'), { 2 })
  end)

  it("uses only literal require calls in src/", function()
    local offenders = {}
    for _, path in ipairs(lua_files()) do
      for _, line in ipairs(dynamic_requires(code(path))) do
        offenders[#offenders + 1] = path .. ":" .. line
      end
    end
    h.assert.equal(table.concat(offenders, ", "), "")
  end)
end)
