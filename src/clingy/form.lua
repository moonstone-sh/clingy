-- Deterministic matcher for declaration value forms.  A cursor is an argv
-- index plus an offset in that word; forms never backtrack after a choice has
-- been selected by a literal prefix.
local M = {}

local function first_literals(atom)
  if atom._tag == "form_literal" then return { atom.text } end
  if atom._tag == "form_sequence" then return first_literals(atom.parts[1]) end
  if atom._tag == "form_choice" then
    local out = {}
    for _, part in ipairs(atom.parts) do
      for _, text in ipairs(first_literals(part)) do table.insert(out, text) end
    end
    return out
  end
  if atom._tag == "form_optional" then return first_literals(atom.part) end
  return {}
end

local function following_literals(parts, index)
  for i = index + 1, #parts do
    local found = first_literals(parts[i])
    if #found > 0 then return found end
    if parts[i]._tag == "form_next_token" then return {} end
  end
  return {}
end

local function match(atom, argv, state, fields, captures, boundary)
  local token = argv[state.word]
  if not token then return nil end
  if atom._tag == "form_literal" then
    if token:sub(state.offset, state.offset + #atom.text - 1) ~= atom.text then return nil end
    return { word = state.word, offset = state.offset + #atom.text }
  end
  if atom._tag == "form_next_token" then
    if state.offset <= #token then return nil end
    if not argv[state.word + 1] then return nil end
    return { word = state.word + 1, offset = 1 }
  end
  if atom._tag == "form_capture" then
    local end_at = #token + 1
    for _, literal in ipairs(boundary or {}) do
      local found = token:find(literal, state.offset, true)
      if found and found < end_at then end_at = found end
    end
    if end_at == state.offset then return nil end
    fields[atom.key] = token:sub(state.offset, end_at - 1)
    captures[atom.key] = atom
    return { word = state.word, offset = end_at }
  end
  if atom._tag == "form_sequence" then
    local cursor = state
    for i, part in ipairs(atom.parts) do
      cursor = match(part, argv, cursor, fields, captures, following_literals(atom.parts, i))
      if not cursor then return nil end
    end
    return cursor
  end
  if atom._tag == "form_choice" then
    for _, part in ipairs(atom.parts) do
      local copied = {}
      for k, v in pairs(fields) do copied[k] = v end
      local copied_captures = {}
      for k, v in pairs(captures) do copied_captures[k] = v end
      local cursor = match(part, argv, state, copied, copied_captures, boundary)
      if cursor then
        for k in pairs(fields) do fields[k] = nil end
        for k, v in pairs(copied) do fields[k] = v end
        for k in pairs(captures) do captures[k] = nil end
        for k, v in pairs(copied_captures) do captures[k] = v end
        return cursor
      end
    end
    return nil
  end
  if atom._tag == "form_optional" then
    local copied = {}
    for k, v in pairs(fields) do copied[k] = v end
    local copied_captures = {}
    for k, v in pairs(captures) do copied_captures[k] = v end
    local cursor = match(atom.part, argv, state, copied, copied_captures, boundary)
    if cursor then
      for k in pairs(fields) do fields[k] = nil end
      for k, v in pairs(copied) do fields[k] = v end
      for k in pairs(captures) do captures[k] = nil end
      for k, v in pairs(copied_captures) do captures[k] = v end
      return cursor
    end
    return state
  end
  error("Unknown form atom: " .. tostring(atom._tag))
end

function M.match(form, argv, word, offset)
  local fields = {}
  local captures = {}
  local cursor = match(form, argv, { word = word, offset = offset or 1 }, fields, captures)
  if not cursor then return nil end
  if cursor.offset <= #(argv[cursor.word] or "") then return nil end
  return fields, cursor.word + 1, captures
end

return M
