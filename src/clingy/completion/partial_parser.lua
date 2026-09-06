--[[
  src/clingy/completion/partial_parser.lua
  Partial Parser Engine: Command Graph traversal, state tracking, and focus resolution.
]]

local response = require("clingy.completion.response")
local context_mod = require("clingy.completion.context")
local discovery = require("clingy.completion.discovery")

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
  for i = start_idx, cword - 1 do
    local token = words[i]
    if token then
      if in_passthrough then
        -- In passthrough mode, just consume
      elseif token == "--" then
        in_passthrough = true
      elseif waiting_option then
        -- Previous option consumed this token as its value
        parsed_args[waiting_option.binding.result_key] = token
        local rk = waiting_option.binding.result_key
        option_counts[rk] = (option_counts[rk] or 0) + 1
        update_ordered_cursor(current_node, waiting_option.binding)
        waiting_option = nil
      elseif token:sub(1, 1) == "-" then
        -- Check for inline option=value: --opt=val or -o=val
        local opt_name, opt_val = token:match("^(%-%-[%w_%-]+)=(.*)$")
        if not opt_name then
          opt_name, opt_val = token:match("^(%-[%w_%-]+)=(.*)$")
        end

        if opt_name then
          local b = current_node.visible_options_by_name and current_node.visible_options_by_name[opt_name]
          if b then
            parsed_args[b.result_key] = opt_val
            option_counts[b.result_key] = (option_counts[b.result_key] or 0) + 1
            update_ordered_cursor(current_node, b)
          end
        else
          -- Standalone flag or option
          local b = current_node.visible_options_by_name and current_node.visible_options_by_name[token]
          if b then
            if b.kind == "option" then
              waiting_option = { binding = b, opt_name = token }
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
          consumed_positionals = consumed_positionals + 1
          local pos_binding = current_node.args and current_node.args[consumed_positionals]
          if pos_binding then
            parsed_args[pos_binding.result_key] = token
            update_ordered_cursor(current_node, pos_binding)
          end
        end
      end
    end
  end

  -- Analyze word at cursor index
  local current_word = words[cword] or ""
  local focus = nil
  local target_binding = nil
  local inline_opt_name = nil
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
      -- Check inline --opt=val
      local opt_name, opt_val = current_word:match("^(%-%-[%w_%-]+)=(.*)$")
      if not opt_name then
        opt_name, opt_val = current_word:match("^(%-[%w_%-]+)=(.*)$")
      end

      if opt_name then
        local b = current_node.visible_options_by_name and current_node.visible_options_by_name[opt_name]
        if b and b.kind == "option" then
          focus = M.FOCUS.OPTION_VALUE
          target_binding = b
          inline_opt_name = opt_name
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

    local has_children = current_node.children and next(current_node.children) ~= nil

    if has_children and pos_binding then
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
    resp:sort()
    return resp
  end

  if focus == M.FOCUS.OPTION_VALUE then
    local provider = discovery.resolve_binding_completion(parse_result.target_binding)
    if provider then
      local p_resp = provider:resolve(ctx)
      if parse_result.inline_opt_name then
        -- Prepend --opt= to candidates
        local inline_prefix = parse_result.inline_opt_name .. "="
        for _, cand in ipairs(p_resp.candidates) do
          cand.value = inline_prefix .. cand.value
          resp:add(cand)
        end
        resp.directive = p_resp.directive
      else
        for _, cand in ipairs(p_resp.candidates) do
          resp:add(cand)
        end
        resp.directive = p_resp.directive
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
          resp:add(cand)
        end
        if p_resp.directive and p_resp.directive ~= response.DIRECTIVE.DEFAULT then
          resp.directive = p_resp.directive
        end
      end
    end
  end

  resp:sort()
  return resp
end

return M
