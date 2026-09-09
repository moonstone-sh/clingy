--[[
  src/clingy/completion/response.lua
  Completion IR: Response, Candidates, and Shell Directive bitmasks.
]]

local M = {}

M.DIRECTIVE = {
  DEFAULT = 0,
  FILENAMES = 1,
  DIRECTORIES = 2,
  NO_FILES = 4,
  NO_SPACE = 8,
}

---Checks if a directive bitmask contains a given flag.
---@param mask integer
---@param flag integer
---@return boolean
function M.has_directive(mask, flag)
  if not mask or not flag or flag <= 0 then return false end
  return (math.floor(mask / flag) % 2) == 1
end

---Adds a directive flag to a bitmask.
---@param mask integer
---@param flag integer
---@return integer
function M.add_directive(mask, flag)
  mask = mask or 0
  if not M.has_directive(mask, flag) then
    return mask + flag
  end
  return mask
end

---Constructs a CompletionCandidate.
---@param val_or_table string|table
---@param description? string
---@param directive? integer
---@return table
function M.candidate(val_or_table, description, directive)
  local function checked_value(value)
    value = tostring(value or "")
    if value:find("[%z\r\n\t]") then
      error("completion candidate values cannot contain NUL, tab, CR, or LF")
    end
    return value
  end

  if type(val_or_table) == "table" then
    return {
      value = checked_value(val_or_table.value or val_or_table[1]),
      description = val_or_table.description or val_or_table.desc or val_or_table[2],
      display = val_or_table.display,
      kind = val_or_table.kind,
      directive = val_or_table.directive or directive or 0,
    }
  end
  return {
    value = checked_value(val_or_table),
    description = description,
    directive = directive or 0,
  }
end

local ResponseMethods = {}
ResponseMethods.__index = ResponseMethods

---Adds a candidate to the completion response.
---@param val_or_table string|table
---@param description? string
---@param directive? integer
---@return table self
function ResponseMethods:add(val_or_table, description, directive)
  local cand = M.candidate(val_or_table, description, directive)
  table.insert(self.candidates, cand)
  if cand.directive and cand.directive ~= M.DIRECTIVE.DEFAULT then
    self.directive = M.add_directive(self.directive, cand.directive)
  end
  return self
end

---Requests shell-native filesystem completion.
---@param kind "path"|"file"|"directory"
---@param opts? { extensions?: string[] }
---@return table self
function ResponseMethods:set_filesystem(kind, opts)
  self.filesystem = {
    kind = kind,
    extensions = opts and opts.extensions or {},
  }
  return self
end

---Adds a directive flag to this response.
---@param flag integer
---@return table self
function ResponseMethods:add_directive(flag)
  self.directive = M.add_directive(self.directive, flag)
  return self
end

---Checks if this response has a directive flag.
---@param flag integer
---@return boolean
function ResponseMethods:has_directive(flag)
  return M.has_directive(self.directive, flag)
end

---Filters candidates by prefix match.
---@param prefix? string
---@return table self
function ResponseMethods:filter_by_prefix(prefix)
  if not prefix or prefix == "" then
    return self
  end
  local filtered = {}
  local p_len = #prefix
  for _, cand in ipairs(self.candidates) do
    if cand.value:sub(1, p_len) == prefix then
      table.insert(filtered, cand)
    end
  end
  self.candidates = filtered
  return self
end

---Sorts candidates alphabetically by value.
---@return table self
function ResponseMethods:sort()
  table.sort(self.candidates, function(a, b)
    return a.value < b.value
  end)
  return self
end

---Constructs a new CompletionResponse.
---@param candidates? table
---@param directive? integer
---@return table CompletionResponse
function M.create(candidates, directive)
  local resp = setmetatable({
    _tag = "completion_response",
    candidates = {},
    directive = directive or M.DIRECTIVE.DEFAULT,
    filesystem = nil,
    replace_prefix = "",
  }, ResponseMethods)

  if candidates then
    for _, c in ipairs(candidates) do
      resp:add(c)
    end
  end

  return resp
end

return M
