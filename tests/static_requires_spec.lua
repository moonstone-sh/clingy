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

-- Build-time tooling loads the user's modules by name and is never part of a
-- built CLI, so it may require dynamically.
local EXEMPT = { "^src/clingy/build/" }

-- Blanks comments and the contents of string literals, keeping quotes and
-- line breaks, so `require("x")` stays recognizable and line numbers stay true.
local function code_only(text)
  local out, i, n = {}, 1, #text
  local function blank(s) return (s:gsub("[^\n]", " ")) end
  while i <= n do
    local ch = text:sub(i, i)
    local long_open = text:match("^%[(=*)%[", i)
    if text:sub(i, i + 1) == "--" then
      local level = text:match("^%-%-%[(=*)%[", i)
      local close = level and select(2, text:find("]" .. level .. "]", i, true))
      local stop = close or (text:find("\n", i, true) or n + 1) - 1
      out[#out + 1] = blank(text:sub(i, stop))
      i = stop + 1
    elseif long_open then
      local _, close = text:find("]" .. long_open .. "]", i, true)
      close = close or n
      out[#out + 1] = '"' .. blank(text:sub(i + 1, close - 1)) .. '"'
      i = close + 1
    elseif ch == '"' or ch == "'" then
      local j = i + 1
      while j <= n do
        local c = text:sub(j, j)
        if c == "\\" then j = j + 2
        elseif c == ch or c == "\n" then break
        else j = j + 1 end
      end
      out[#out + 1] = ch .. text:sub(i + 1, j - 1):gsub("[^\n]", "x") .. ch
      i = j + 1
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

local function dynamic_requires(text)
  text = code_only(text)
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

local function read(path)
  local f = assert(io.open(path, "r"))
  local text = f:read("*a")
  f:close()
  return text
end

describe("static module loading", function()
  it("finds require passed as a value", function()
    h.assert.same(dynamic_requires('local a = require("a")\nlocal ok = pcall(require, "b")\nx.require(y)'), { 2 })
  end)

  it("ignores require in strings and comments", function()
    h.assert.same(dynamic_requires('local s = "require(%q)"\n-- pcall(require, x)\nlocal t = [[require(y)]]\nlocal a = require("a")'), {})
  end)

  it("uses only literal require calls in src/", function()
    local offenders = {}
    for _, path in ipairs(lua_files()) do
      local exempt = false
      for _, pattern in ipairs(EXEMPT) do
        if path:match(pattern) then exempt = true end
      end
      if not exempt then
        for _, line in ipairs(dynamic_requires(read(path))) do
          offenders[#offenders + 1] = path .. ":" .. line
        end
      end
    end
    h.assert.equal(table.concat(offenders, ", "), "")
  end)
end)
