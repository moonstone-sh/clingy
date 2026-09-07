---Fixed, single-argv-token positional pattern compilation and matching.
---This module deliberately knows nothing about command routing or schemas: the
---compiler owns structure, while the parser owns per-capture validation.
local M = {}

local function pattern_escape(value)
  return (value:gsub("([^%w])", "%%%1"))
end

local function pattern_display(items)
  local parts = {}
  for _, item in ipairs(items) do
    if item._tag == "capture" then
      table.insert(parts, "{" .. item.label .. "}")
    else
      table.insert(parts, item.text)
    end
  end
  return table.concat(parts)
end

---Compiles a c.compose AST into an anchored lexical pattern.
---Only labelled captures are variable. A capture must have a following fixed
---fragment unless it is final, so no token can require guessing a boundary
---between two captures.
---@param declaration table
---@return table
function M.compile(declaration)
  if type(declaration) ~= "table" or declaration._tag ~= "compose" then
    error("Internal Error: expected a c.compose declaration")
  end

  local source_items = declaration.items
  if type(source_items) ~= "table" or #source_items == 0 then
    error("Compilation Error: c.compose requires one or more pattern items")
  end

  local items = {}
  local labels = {}
  local seen_labels = {}
  local previous_was_capture = false

  for _, item in ipairs(source_items) do
    if type(item) ~= "table" then
      error("Compilation Error: c.compose items must be c.literal(...), c.separator(...), or c.label(..., c.capture(...))")
    end

    if item._tag == "literal" or item._tag == "compose_separator" then
      if type(item.text) ~= "string" or item.text == "" then
        error("Compilation Error: c.compose fixed pattern text must be non-empty")
      end
      table.insert(items, {
        _tag = item._tag,
        text = item.text,
        trim = item._tag == "compose_separator" and item.trim ~= false or false,
      })
      previous_was_capture = false
    elseif item._tag == "capture" then
      if type(item.label) ~= "string" or item.label:match("^%s*$") then
        error("Compilation Error: c.compose captures require a non-empty c.label")
      end
      if previous_was_capture then
        error("Compilation Error: c.compose has adjacent captures; insert c.literal(...) or c.separator(...) to define the boundary")
      end
      if seen_labels[item.label] then
        error(string.format("Compilation Error: c.compose has duplicate capture label '%s'", item.label))
      end
      seen_labels[item.label] = true
      table.insert(labels, item.label)
      table.insert(items, {
        _tag = "capture",
        label = item.label,
        schema = item.schema,
        source = item.source,
      })
      previous_was_capture = true
    else
      error("Compilation Error: c.compose items must be c.literal(...), c.separator(...), or c.label(..., c.capture(...))")
    end
  end

  if #labels == 0 then
    error("Compilation Error: c.compose requires at least one labelled capture")
  end

  local lexical = { "^" }
  for index, item in ipairs(items) do
    if item._tag == "capture" then
      -- The final capture owns the remaining token text. Earlier captures are
      -- bounded by the next required fixed fragment and therefore non-greedy.
      table.insert(lexical, index == #items and "(.*)" or "(.-)")
    elseif item._tag == "compose_separator" and item.trim then
      table.insert(lexical, "%s*" .. pattern_escape(item.text) .. "%s*")
    else
      table.insert(lexical, pattern_escape(item.text))
    end
  end
  table.insert(lexical, "$")

  return {
    items = items,
    labels = labels,
    lexical_pattern = table.concat(lexical),
    display = pattern_display(items),
  }
end

---Matches the complete argv token and returns raw substrings by capture label.
---@param token string
---@param pattern table
---@return table|nil
function M.match(token, pattern)
  local captures = { string.match(token, pattern.lexical_pattern) }
  if #captures ~= #pattern.labels then
    return nil
  end

  local result = {}
  for index, label in ipairs(pattern.labels) do
    result[label] = captures[index]
  end
  return result
end

return M
