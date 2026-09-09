-- Typed, line-oriented completion protocol shared by every shell bridge.
-- Values may contain punctuation, spaces, quotes, and backslashes. Control
-- characters used as record delimiters are deliberately outside the domain.
local response = require("clingy.completion.response")

local M = {}

local function clean_description(value)
  if value == nil then return "" end
  return tostring(value):gsub("[%z\r\n\t]", " ")
end

local function checked_field(value, subject)
  value = tostring(value or "")
  if value:find("[%z\r\n\t]") then
    error(subject .. " cannot contain NUL, tab, CR, or LF")
  end
  return value
end

function M.render(resp, descriptions)
  local lines = { "V\t2" }
  local directives = {}
  if resp:has_directive(response.DIRECTIVE.FILENAMES) then directives[#directives + 1] = "filenames" end
  if resp:has_directive(response.DIRECTIVE.DIRECTORIES) then directives[#directives + 1] = "dirnames" end
  if resp:has_directive(response.DIRECTIVE.NO_FILES) then directives[#directives + 1] = "nofiles" end
  if resp:has_directive(response.DIRECTIVE.NO_SPACE) then directives[#directives + 1] = "nospace" end

  if #directives > 0 or resp.filesystem then
    local filesystem = resp.filesystem or {}
    local extensions = filesystem.extensions or {}
    local directive_field = #directives > 0 and table.concat(directives, ",") or "-"
    local kind_field = filesystem.kind and checked_field(filesystem.kind, "filesystem kind") or "-"
    local replace_field = resp.replace_prefix ~= "" and checked_field(resp.replace_prefix, "completion replacement prefix") or "-"
    local extensions_field = #extensions > 0 and checked_field(table.concat(extensions, ","), "completion extensions") or "-"
    lines[#lines + 1] = table.concat({
      "D",
      directive_field,
      kind_field,
      replace_field,
      extensions_field,
    }, "\t")
  end

  for _, cand in ipairs(resp.candidates or {}) do
    local fields = { "C", checked_field(cand.value, "completion candidate value") }
    if descriptions then fields[3] = clean_description(cand.description) end
    lines[#lines + 1] = table.concat(fields, "\t")
  end
  return table.concat(lines, "\n")
end

return M
