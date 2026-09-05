local M = {}

function M.deep_copy(orig, seen)
  if type(orig) ~= "table" then
    return orig
  end
  seen = seen or {}
  if seen[orig] then
    return seen[orig]
  end

  local copy = {}
  seen[orig] = copy

  for orig_key, orig_value in next, orig, nil do
    copy[M.deep_copy(orig_key, seen)] = M.deep_copy(orig_value, seen)
  end

  local mt = getmetatable(orig)
  if mt then
    setmetatable(copy, M.deep_copy(mt, seen))
  end

  return copy
end

function M.shallow_copy(orig)
  if type(orig) ~= "table" then return orig end
  local copy = {}
  for k, v in pairs(orig) do
    copy[k] = v
  end
  return copy
end

function M.is_array(tbl)
  if type(tbl) ~= "table" then return false end
  local count = 0
  for _ in pairs(tbl) do
    count = count + 1
  end
  return count == #tbl
end

---Derives canonical key from a list of option/flag names.
---Section 14: Canonical result name is derived from the longest long-form alias.
---e.g. {"-v", "--verbose"} -> "verbose"
---e.g. {"-n"} -> "n"
function M.derive_key(names)
  if type(names) == "string" then
    names = { names }
  end
  local longest_long = nil
  local shortest_short = nil

  for _, name in ipairs(names) do
    if name:sub(1, 2) == "--" then
      local bare = name:sub(3)
      if not longest_long or #bare > #longest_long then
        longest_long = bare
      end
    elseif name:sub(1, 1) == "-" then
      local bare = name:sub(2)
      if not shortest_short or #bare < #shortest_short then
        shortest_short = bare
      end
    else
      -- bare name (e.g. positional arg)
      return name
    end
  end

  local chosen = longest_long or shortest_short
  if not chosen then
    error("Could not derive key from names: " .. table.concat(names, ", "))
  end
  return chosen:gsub("%-", "_")
end

---Creates a dual-access table that allows accessing foo_bar as foo-bar and vice versa.
function M.create_args_table(initial)
  local t = {}
  for k, v in pairs(initial or {}) do
    t[k] = v
    if type(k) == "string" then
      local with_dash = k:gsub("_", "-")
      local with_under = k:gsub("-", "_")
      if t[with_dash] == nil then t[with_dash] = v end
      if t[with_under] == nil then t[with_under] = v end
    end
  end
  return t
end

function M.format_issue(issue)
  local path_str = ""
  if issue.path and #issue.path > 0 then
    local segments = {}
    for _, p in ipairs(issue.path) do
      table.insert(segments, tostring(p))
    end
    path_str = table.concat(segments, ".") .. ": "
  end
  return path_str .. (issue.message or "Validation failed")
end

return M
