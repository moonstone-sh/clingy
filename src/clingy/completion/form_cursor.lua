-- Locates the capture owning the active cursor inside a form. Unlike the
-- strict runtime matcher, this walker accepts an incomplete final literal or
-- capture and follows c.next_token() across any number of argv words.
local M = {}

local function first_literals(atom)
  if atom._tag == "form_literal" then return { atom.text } end
  if atom._tag == "form_sequence" then return first_literals(atom.parts[1]) end
  if atom._tag == "form_choice" then
    local out = {}
    for _, part in ipairs(atom.parts) do
      for _, text in ipairs(first_literals(part)) do out[#out + 1] = text end
    end
    return out
  end
  if atom._tag == "form_optional" then return first_literals(atom.part) end
  return {}
end

local function following_literals(parts, index)
  for i = index + 1, #parts do
    local literals = first_literals(parts[i])
    if #literals > 0 then return literals end
    if parts[i]._tag == "form_next_token" then return {} end
  end
  return {}
end

local function walk(atom, words, state, cword, boundary)
  local token = words[state.word] or ""
  if state.word > cword then return { state = state, pending = true } end

  if atom._tag == "form_literal" then
    local remaining = token:sub(state.offset)
    if state.word == cword and #remaining < #atom.text
        and atom.text:sub(1, #remaining) == remaining then
      return {
        state = { word = state.word, offset = #token + 1 },
        literal = atom.text,
        prefix = remaining,
        form_prefix = token:sub(1, state.offset - 1),
      }
    end
    if token:sub(state.offset, state.offset + #atom.text - 1) ~= atom.text then return nil end
    return { state = { word = state.word, offset = state.offset + #atom.text } }
  end

  if atom._tag == "form_next_token" then
    if state.offset <= #token or state.word >= cword then return nil end
    return { state = { word = state.word + 1, offset = 1 } }
  end

  if atom._tag == "form_capture" then
    local end_at = #token + 1
    for _, literal in ipairs(boundary or {}) do
      local found = token:find(literal, state.offset, true)
      if found and found < end_at then end_at = found end
    end
    if end_at < #token + 1 then
      if end_at == state.offset then return nil end
      return { state = { word = state.word, offset = end_at } }
    end
    if state.word < cword then
      if state.offset > #token then return nil end
      return { state = { word = state.word, offset = #token + 1 } }
    end
    return {
      state = { word = state.word, offset = #token + 1 },
      target = atom,
      prefix = token:sub(state.offset),
      form_prefix = token:sub(1, state.offset - 1),
    }
  end

  if atom._tag == "form_sequence" then
    local result = { state = state }
    for i, part in ipairs(atom.parts) do
      result = walk(part, words, result.state, cword, following_literals(atom.parts, i))
      if not result or result.target or result.literal or result.pending then return result end
    end
    return result
  end

  if atom._tag == "form_choice" then
    local literal_results = {}
    for _, part in ipairs(atom.parts) do
      local result = walk(part, words, state, cword, boundary)
      if result and result.target then return result end
      if result and result.literal then literal_results[#literal_results + 1] = result end
      if result and not result.literal and not result.pending then return result end
    end
    if #literal_results > 0 then
      local first = literal_results[1]
      first.literals = {}
      for _, result in ipairs(literal_results) do first.literals[#first.literals + 1] = result.literal end
      return first
    end
    return nil
  end

  if atom._tag == "form_optional" then
    return walk(atom.part, words, state, cword, boundary) or { state = state }
  end

  error("Unknown form atom: " .. tostring(atom._tag))
end

function M.locate(form, words, start_word, start_offset, cword)
  local result = walk(form, words, { word = start_word, offset = start_offset or 1 }, cword, {})
  if not result or (not result.target and not result.literal) then return nil end
  return result.target, result.prefix, result.form_prefix, result.literal, result.literals
end

return M
