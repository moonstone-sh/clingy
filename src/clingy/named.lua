---Shared lexical rules for named option and flag tokens.
local M = {}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

---Removes surrounding whitespace from an attached value when the declaration
---uses the default trimming policy.
---@param value string
---@param binding table
---@return string
function M.normalize_attached_value(value, binding)
  local policy = binding and binding.separator_policy
  if not policy or policy.trim ~= false then
    return value:match("^%s*(.-)%s*$")
  end
  return value
end

---Splits an attached option value according to the binding's declared policy.
---An exact alias always wins. This deliberately permits legacy aliases which
---themselves contain punctuation such as '=' or ':'. Candidates are ordered
---deterministically by longest alias then longest separator.
---@param token string
---@param bindings_by_name table?
---@return string name
---@return string? value
---@return integer? separator_pos
---@return string? separator
function M.split_attached_value(token, bindings_by_name)
  if bindings_by_name and bindings_by_name[token] then
    return token, nil, nil, nil
  end

  local candidates = {}
  for alias, binding in pairs(bindings_by_name or {}) do
    local policy = binding.separator_policy or {}
    for _, separator in ipairs(policy.attached or {}) do
      local trailing = token:sub(#alias + 1)
      -- A zero-width separator describes an adjacent value, never a bare
      -- alias. Bare aliases retain normal detached-value handling.
      if starts_with(token, alias)
          and (#separator > 0 or #trailing > 0)
          and starts_with(trailing, separator) then
        table.insert(candidates, { alias = alias, separator = separator })
      end
    end
  end

  table.sort(candidates, function(a, b)
    if #a.alias ~= #b.alias then return #a.alias > #b.alias end
    if #a.separator ~= #b.separator then return #a.separator > #b.separator end
    if a.alias ~= b.alias then return a.alias < b.alias end
    return a.separator < b.separator
  end)

  local candidate = candidates[1]
  if candidate then
    local separator_pos = #candidate.alias + 1
    return candidate.alias, token:sub(separator_pos + #candidate.separator), separator_pos, candidate.separator
  end
  return token, nil, nil, nil
end

---Matches a c.define record token by its literal prefix. Prefixes are ordered
---longest-first so a more specific declaration always owns the token.
---@param token string
---@param definitions table?
---@return table? match
function M.match_define(token, definitions)
  local candidates = {}
  for _, binding in ipairs(definitions or {}) do
    local pattern = binding.define_pattern
    if pattern and starts_with(token, pattern.prefix) then
      table.insert(candidates, binding)
    end
  end
  table.sort(candidates, function(a, b)
    return #a.define_pattern.prefix > #b.define_pattern.prefix
  end)
  local binding = candidates[1]
  if not binding then return nil end

  local pattern = binding.define_pattern
  local suffix = token:sub(#pattern.prefix + 1)
  if suffix == "" then
    return { binding = binding, error = "requires an adjacent name" }
  end

  local separator_at, separator_text
  for _, separator in ipairs(pattern.attached or {}) do
    local at = suffix:find(separator, 1, true)
    if at and (not separator_at or at < separator_at
        or (at == separator_at and #separator > #separator_text)) then
      separator_at, separator_text = at, separator
    end
  end
  if separator_at then
    local name = suffix:sub(1, separator_at - 1)
    local value = suffix:sub(separator_at + #separator_text)
    if name == "" then
      return { binding = binding, error = "requires an adjacent name" }
    end
    if value == "" then
      return { binding = binding, error = "requires a value" }
    end
    return { binding = binding, name = name, value = value, separator = separator_text }
  end
  if suffix == "" then
    return { binding = binding, error = "requires an adjacent name" }
  end
  if pattern.detached then
    return { binding = binding, name = suffix, value = nil, separator = " " }
  end
  return { binding = binding, error = "requires a value separator" }
end

return M
