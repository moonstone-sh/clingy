--[[
  src/clingy/completion/partial_parser.lua
  Partial Parser Engine: Command Graph traversal, state tracking, and focus resolution.
]]

local response = require("clingy.completion.response")
local context_mod = require("clingy.completion.context")
local discovery = require("clingy.completion.discovery")
local named = require("clingy.named")
local form = require("clingy.form")
local form_cursor = require("clingy.completion.form_cursor")
local providers = require("clingy.completion.providers")

local M = {}

M.FOCUS = {
  SUBCOMMAND = "FOCUS_SUBCOMMAND",
  OPTION_NAME = "FOCUS_OPTION_NAME",
  OPTION_VALUE = "FOCUS_OPTION_VALUE",
  POSITIONAL = "FOCUS_POSITIONAL",
  PASSTHROUGH = "FOCUS_PASSTHROUGH",
}

---Traverses the router to identify parsing state and cursor focus.
---@param router table CompiledRouter or App
---@param words string[] Array of command line words
---@param cword? integer 1-indexed word currently being completed (defaults to #words)
---@return table ParseResult
function M.parse_partial(router, words, cword)
  local compiled_root = router.root or (router._graph and router._graph.root)
  assert(compiled_root, "router must have a compiled root node")

  words = words or {}
  cword = cword or #words
  if cword < 1 then cword = 1 end

  -- Determine start index: skip binary name if present
  local start_idx = 1
  if #words > 0 then
    local w1 = words[1]
    local app_name = router.name or (router._graph and router._graph.name) or compiled_root.name
    if w1 == app_name or w1:match("[/\\]" .. app_name .. "$") then
      start_idx = 2
    elseif not compiled_root.children[w1] and (not compiled_root.child_names_map or not compiled_root.child_names_map[w1]) then
      -- First token does not match any root subcommand; treat as binary name if more words follow
      if #words >= 2 then
        start_idx = 2
      end
    end
  end

  local current_node = compiled_root
  local route = { current_node }
  local parsed_args = {}
  local option_counts = {}
  local consumed_positionals = 0
  local ordered_cursor = 1
  local in_passthrough = false
  local waiting_option = nil
  local active_form = nil

  local function update_ordered_cursor(node, binding)
    if node.mode == "ordered" and node.declarations_order then
      for idx, decl in ipairs(node.declarations_order) do
        if decl == binding or decl.result_key == binding.result_key then
          ordered_cursor = idx
          break
        end
      end
    end
  end

  -- Process completed tokens prior to cursor
  local i = start_idx
  while i < cword do
    local token = words[i]
    if token then
      if in_passthrough then
        -- In passthrough mode, just consume
      elseif current_node.end_capture and token == current_node.end_capture.terminator then
        in_passthrough = true
      elseif token == "--" then
        if current_node.end_capture and current_node.end_capture.legacy_passthrough then
          in_passthrough = true
        end
      elseif waiting_option then
        -- Previous option consumed this token as its value
        parsed_args[waiting_option.binding.result_key] = token
        local rk = waiting_option.binding.result_key
        option_counts[rk] = (option_counts[rk] or 0) + 1
        update_ordered_cursor(current_node, waiting_option.binding)
        waiting_option = nil
      elseif token:sub(1, 1) == "-" then
        -- Match runtime's exact-alias precedence and '=' / ':' attachments.
        local bindings = current_node.visible_options_by_name
        local opt_name, opt_val, separator_pos = named.split_attached_value(token, bindings)
        local b = bindings and bindings[opt_name]

        if separator_pos then
          if b and b.kind == "option" then
            parsed_args[b.result_key] = opt_val
            option_counts[b.result_key] = (option_counts[b.result_key] or 0) + 1
            update_ordered_cursor(current_node, b)
          end
        else
          -- Standalone flag or option
          if b then
            if b.kind == "option" then
              waiting_option = { binding = b, opt_name = opt_name }
            elseif b.kind == "flag" then
              parsed_args[b.result_key] = true
              option_counts[b.result_key] = (option_counts[b.result_key] or 0) + 1
              update_ordered_cursor(current_node, b)
            end
          end
        end
      else
        -- Token does not start with '-': check subcommand transition
        local child_node = current_node.children and current_node.children[token]
        if not child_node and current_node.child_names_map and current_node.child_names_map[token] then
          local child_id = current_node.child_names_map[token]
          child_node = (router.nodes or (router._graph and router._graph.nodes))[child_id]
        end

        if child_node then
          current_node = child_node
          table.insert(route, current_node)
          consumed_positionals = 0
          ordered_cursor = 1
        else
          -- Positional argument consumption
          local pos_binding = current_node.args and current_node.args[consumed_positionals + 1]
          if pos_binding then
            if pos_binding.form then
              local fields, next_i = form.match(pos_binding.form, words, i)
              if fields and next_i <= cword then
                consumed_positionals = consumed_positionals + 1
                parsed_args[pos_binding.result_key] = fields
                update_ordered_cursor(current_node, pos_binding)
                i = next_i - 1
              else
                active_form = { binding = pos_binding, start_word = i, start_offset = 1 }
                i = cword - 1
              end
            else
              consumed_positionals = consumed_positionals + 1
              parsed_args[pos_binding.result_key] = token
              update_ordered_cursor(current_node, pos_binding)
            end
          end
        end
      end
    end
    i = i + 1
  end

  -- Analyze word at cursor index
  local current_word = words[cword] or ""
  local focus = nil
  local target_binding = nil
  local inline_opt_name = nil
  local inline_separator = nil
  local prefix = current_word

  if in_passthrough then
    focus = M.FOCUS.PASSTHROUGH
  elseif waiting_option then
    focus = M.FOCUS.OPTION_VALUE
    target_binding = waiting_option.binding
    prefix = current_word
  elseif current_word:sub(1, 1) == "-" then
    if current_node.mode == "leading" and consumed_positionals > 0 then
      -- In leading mode, options cannot appear after positional argument!
      focus = M.FOCUS.PASSTHROUGH
    else
      -- Match runtime's exact-alias precedence and '=' / ':' attachments.
      local bindings = current_node.visible_options_by_name
      local opt_name, opt_val, separator_pos, separator = named.split_attached_value(current_word, bindings)
      local b = bindings and bindings[opt_name]

      if separator_pos then
        if b and b.kind == "option" then
          focus = M.FOCUS.OPTION_VALUE
          target_binding = b
          inline_opt_name = opt_name
          inline_separator = separator
          prefix = opt_val
        else
          focus = M.FOCUS.OPTION_NAME
          prefix = current_word
        end
      else
        focus = M.FOCUS.OPTION_NAME
        prefix = current_word
      end
    end
  else
    -- Current word is not starting with '-'
    local next_pos = consumed_positionals + 1
    local pos_binding = current_node.args and current_node.args[next_pos]

    if active_form then
      local capture, capture_prefix, form_prefix, literal, literals = form_cursor.locate(
        active_form.binding.form, words, active_form.start_word, active_form.start_offset, cword)
      if capture or literal then
        target_binding = {
          schema = capture and capture.schema or nil,
          completion = literal and { origin = "explicit", provider = providers.values(literals or { literal }) }
            or (capture.complete and { origin = "explicit", provider = capture.complete } or nil),
        }
        focus = M.FOCUS.POSITIONAL
        prefix = capture_prefix
        target_binding.form_prefix = form_prefix ~= "" and form_prefix or nil
      end
    end

    if not focus and pos_binding and pos_binding.form then
      local capture, capture_prefix, form_prefix, literal, literals = form_cursor.locate(pos_binding.form, words, cword, 1, cword)
      if capture or literal then
        target_binding = {
          schema = capture and capture.schema or nil,
          completion = literal and { origin = "explicit", provider = providers.values(literals or { literal }) }
            or (capture.complete and { origin = "explicit", provider = capture.complete } or nil),
        }
        focus = M.FOCUS.POSITIONAL
        prefix = capture_prefix
        -- Keep the already-matched literal segment so rendered candidates are
        -- valid argv words rather than bare capture fragments.
        target_binding.form_prefix = form_prefix ~= "" and form_prefix or nil
      end
    end

    local has_children = current_node.children and next(current_node.children) ~= nil

    if focus == M.FOCUS.POSITIONAL then
      -- A form capture has already selected the completion target.
    elseif has_children and pos_binding then
      focus = "FOCUS_SUBCOMMAND_OR_POSITIONAL"
      target_binding = pos_binding
    elseif has_children then
      focus = M.FOCUS.SUBCOMMAND
    elseif pos_binding then
      focus = M.FOCUS.POSITIONAL
      target_binding = pos_binding
    else
      -- Check repeated last positional
      local last_arg = current_node.args and current_node.args[#current_node.args]
      if last_arg and (last_arg.occurrence.max == nil or last_arg.aggregate == "array") then
        focus = M.FOCUS.POSITIONAL
        target_binding = last_arg
      else
        if current_node.visible_options_by_name and next(current_node.visible_options_by_name) ~= nil then
          focus = M.FOCUS.OPTION_NAME
        else
          focus = M.FOCUS.SUBCOMMAND
        end
      end
    end
  end

  return {
    current_node = current_node,
    route = route,
    args = parsed_args,
    focus = focus,
    target_binding = target_binding,
    inline_opt_name = inline_opt_name,
    inline_separator = inline_separator,
    prefix = prefix,
    words = words,
    cword = cword,
    consumed_positionals = consumed_positionals,
    option_counts = option_counts,
    ordered_cursor = ordered_cursor,
  }
end

---Resolves candidates based on the partial parse result.
---@param parse_result table Output of parse_partial
---@return table CompletionResponse
function M.resolve_candidates(parse_result)
  local resp = response.create()
  local node = parse_result.current_node
  local focus = parse_result.focus
  local prefix = parse_result.prefix or ""

  local ctx = context_mod.create({
    args = parse_result.args,
    prefix = prefix,
    route = parse_result.route,
    target_node = node,
    binding = parse_result.target_binding,
    words = parse_result.words,
    cword = parse_result.cword,
  })

  local function merge_provider_metadata(provider_response, replace_prefix)
    for _, flag in pairs(response.DIRECTIVE) do
      if flag ~= response.DIRECTIVE.DEFAULT and provider_response:has_directive(flag) then
        resp:add_directive(flag)
      end
    end
    if provider_response.filesystem then
      resp.filesystem = provider_response.filesystem
      resp.replace_prefix = replace_prefix or provider_response.replace_prefix or ""
    end
  end

  if focus == M.FOCUS.PASSTHROUGH then
    return resp
  end

  if focus == M.FOCUS.OPTION_NAME then
    -- In leading mode, options cannot appear after positionals
    if node.mode == "leading" and parse_result.consumed_positionals and parse_result.consumed_positionals > 0 then
      return resp
    end

    local decl_index_map = {}
    if node.mode == "ordered" and node.declarations_order then
      for idx, decl in ipairs(node.declarations_order) do
        decl_index_map[decl] = idx
        if decl.result_key then
          decl_index_map[decl.result_key] = idx
        end
      end
    end

    -- Complete visible option and flag names
    local seen = {}
    for name, b in pairs(node.visible_options_by_name or {}) do
      if not seen[name] and name:sub(1, #prefix) == prefix then
        local count = parse_result.option_counts and parse_result.option_counts[b.result_key] or 0
        local is_repeatable = (b.occurrence and b.occurrence.max == nil)
                           or (b.occurrence and b.occurrence.max and b.occurrence.max > 1)
                           or (b.aggregate == "array")
        local cardinality_allowed = true
        if not is_repeatable and count >= 1 then
          cardinality_allowed = false
        elseif is_repeatable and b.occurrence and b.occurrence.max and count >= b.occurrence.max then
          cardinality_allowed = false
        end

        local ordered_allowed = true
        if node.mode == "ordered" and parse_result.ordered_cursor then
          local b_idx = decl_index_map[b] or decl_index_map[b.result_key]
          if b_idx then
            if b_idx < parse_result.ordered_cursor then
              ordered_allowed = false
            elseif b_idx == parse_result.ordered_cursor and count >= 1 and not is_repeatable then
              ordered_allowed = false
            end
          end
        end

        if cardinality_allowed and ordered_allowed then
          seen[name] = true
          local desc = (b.metadata and b.metadata.description) or (b.schema and b.schema.description)
          resp:add(name, desc)
        end
      end
    end
    if node.end_capture and node.end_capture.terminator
        and node.end_capture.terminator:sub(1, #prefix) == prefix then
      resp:add(node.end_capture.terminator, "end capture")
    end
    resp:sort()
    return resp
  end

  if focus == M.FOCUS.OPTION_VALUE then
    if not parse_result.inline_opt_name and parse_result.target_binding
        and parse_result.target_binding.separator_policy
        and not parse_result.target_binding.separator_policy.detached then
      return resp
    end
    local provider = discovery.resolve_binding_completion(parse_result.target_binding)
    if provider then
      local p_resp = provider:resolve(ctx)
      if parse_result.inline_opt_name then
        -- Preserve the user's attached-value separator in candidates.
        local inline_prefix = parse_result.inline_opt_name .. (parse_result.inline_separator or "=")
        for _, cand in ipairs(p_resp.candidates) do
          cand.value = inline_prefix .. cand.value
          resp:add(cand)
        end
        merge_provider_metadata(p_resp, inline_prefix)
      else
        for _, cand in ipairs(p_resp.candidates) do
          resp:add(cand)
        end
        merge_provider_metadata(p_resp)
      end
    end
    return resp
  end

  if focus == M.FOCUS.SUBCOMMAND or focus == "FOCUS_SUBCOMMAND_OR_POSITIONAL" then
    -- Add child command candidates
    if node.children then
      for child_name, child_node in pairs(node.children) do
        if child_name:sub(1, #prefix) == prefix then
          local hidden = child_node.metadata and child_node.metadata.hidden
          if not hidden then
            local desc = child_node.metadata and child_node.metadata.description
            resp:add(child_name, desc)
          end
        end
      end
    end
  end

  if focus == M.FOCUS.POSITIONAL or focus == "FOCUS_SUBCOMMAND_OR_POSITIONAL" then
    if parse_result.target_binding then
      local provider = discovery.resolve_binding_completion(parse_result.target_binding)
      if provider then
        local p_resp = provider:resolve(ctx)
        for _, cand in ipairs(p_resp.candidates) do
          if parse_result.target_binding.form_prefix then
            cand.value = parse_result.target_binding.form_prefix .. cand.value
          end
          resp:add(cand)
        end
        merge_provider_metadata(p_resp, parse_result.target_binding.form_prefix)
      end
    end
  end

  resp:sort()
  return resp
end

return M
