local util = require("clingy.util")
local adapter = require("clingy.adapter")
local named = require("clingy.named")
local form = require("clingy.form")
local routing = require("clingy.routing")

local M = {}

---Parses argv against a compiled Command Graph IR.
---@param graph table Compiled Command Graph from compiler.compile
---@param argv table Array of string arguments
---@return table Parsed result: { route = {...}, args = {...}, passthrough = {...}, target_node = ... }
function M.parse(graph, argv)
  argv = argv or {}

  local current_node = graph.root
  local route = {}
  local route_segment_by_node = {}

  local active_segment = nil
  local route_segment_by_name = {}

  local function add_route_segment(node_ir)
    local segment = {
      node = node_ir.name,
      node_ir = node_ir,
      args = {},
      raw_occurrences = {},
    }
    table.insert(route, segment)
    route_segment_by_node[node_ir] = segment
    route_segment_by_name[node_ir.name] = segment
    if node_ir.id then
      route_segment_by_name[node_ir.id] = segment
    end
    active_segment = segment
    return segment
  end

  active_segment = add_route_segment(current_node)

  -- Track occurrences across declarations: decl -> count
  local occurrence_counts = {}
  local function note_occurrence(decl)
    local count = occurrence_counts[decl] or 0
    local max = decl.occurrence and decl.occurrence.max
    if max ~= nil and count >= max then
      error(string.format("Declaration '%s' may occur at most %d time(s)",
        decl.names and decl.names[1] or decl.name or decl.result_key, max))
    end
    occurrence_counts[decl] = count + 1
  end
  -- Track collected values: decl -> list of validated values
  local collected_values = {}
  -- Track positionals consumed per segment: segment -> int
  local positionals_consumed = {}
  -- Track current positional index per segment: segment -> int
  local positional_cursor = {}
  -- Track ordered mode cursor per segment: segment -> int
  local ordered_cursor = {}

  local passthrough_tokens = {}
  local passthrough_active = false
  local end_capture = nil
  local options_closed = false

  local i = 1

  while i <= #argv do
    local token = argv[i]

    if end_capture then
      table.insert(end_capture.tokens, token)
      i = i + 1
    elseif current_node.end_capture and not current_node.end_capture.legacy_passthrough
        and token == current_node.end_capture.terminator then
      local policy = current_node.end_capture
      local capture = { policy = policy, tokens = {} }
      if policy.forward == "complete" then
        table.insert(capture.tokens, token)
      end
      end_capture = capture
      i = i + 1
    elseif token == "--" then
      -- Legacy passthrough retains its historical delayed capture behavior so
      -- required positionals after the delimiter can still be satisfied.
      options_closed = true
      i = i + 1
      local has_unmet_pos = false
      for _, arg_decl in ipairs(current_node.args) do
        local cnt = occurrence_counts[arg_decl] or 0
        local min = arg_decl.occurrence.min or 1
        if cnt < min then
          has_unmet_pos = true
          break
        end
      end
      if not has_unmet_pos then
        if current_node.end_capture and current_node.end_capture.legacy_passthrough then
          passthrough_active = true
          end_capture = { policy = current_node.end_capture, tokens = passthrough_tokens }
        end
      end
    else
      local seg_pos_consumed = positionals_consumed[active_segment] or 0
      local is_leading = current_node.mode == "leading"

      -- Check if token is an option or flag (starts with '-' and not pure '-')
      local is_option_like = token:sub(1, 1) == "-" and #token > 1

      -- Numeric literals like -1, -42 are not option-like unless explicitly declared
      if token:match("^%-[0-9]") and not current_node.visible_options_by_name[token] then
        is_option_like = false
      end

      -- If options were closed by '--', do not treat as option
      if options_closed then
        is_option_like = false
      end

      -- In leading mode, once positional consumption begins, option recognition stops
      if is_leading and seg_pos_consumed > 0 and not options_closed then
        -- Check if token exactly matches a visible named declaration or cluster.
        local opt_name, _, attached_separator_pos = named.split_attached_value(token, current_node.visible_options_by_name)

        if current_node.visible_options_by_name[opt_name] then
          error(string.format("Misplaced option error: '%s' is a valid option for command '%s', but leading-mode option parsing ended after positional consumption began", token, current_node.name))
        end

        if current_node.short_clusters and token:match("^%-[a-zA-Z0-9]+$") and not attached_separator_pos and not token:match("^%-%-") then
          local all_flags = true
          for ch_idx = 2, #token do
            local short_name = "-" .. token:sub(ch_idx, ch_idx)
            local ch_decl = current_node.visible_options_by_name[short_name]
            if not (ch_decl and ch_decl.kind == "flag") then
              all_flags = false
              break
            end
          end
          if all_flags and #token > 1 then
            error(string.format("Misplaced option error: '%s' is a valid option cluster for command '%s', but leading-mode option parsing ended after positional consumption began", token, current_node.name))
          end
        end

        -- Otherwise, it is not a visible option/cluster; allow positional grammar to consume it
        is_option_like = false
      end

      if is_option_like then
        -- Handle attached values in either --opt=value or --opt:value form.
        local opt_name, attached_val, attached_separator_pos = named.split_attached_value(token, current_node.visible_options_by_name)

        local decl = current_node.visible_options_by_name[opt_name]
        local form_offset = nil
        if not decl then
          local matches = {}
          for alias, candidate in pairs(current_node.visible_options_by_name) do
            if candidate.form and token:sub(1, #alias) == alias and #token > #alias then
              table.insert(matches, { alias = alias, binding = candidate })
            end
          end
          table.sort(matches, function(a, b) return #a.alias > #b.alias end)
          if matches[1] then
            opt_name, decl = matches[1].alias, matches[1].binding
            form_offset = #opt_name + 1
          end
        end

        if decl then
          -- Check ordered mode constraint
          if current_node.mode == "ordered" then
            local ord_cur = ordered_cursor[active_segment] or 1
            local decls_order = current_node.declarations_order or {}
            local matched_ord_idx = nil
            for d_idx = ord_cur, #decls_order do
              local candidate = decls_order[d_idx]
              if candidate == decl then
                matched_ord_idx = d_idx
                break
              elseif candidate.occurrence and candidate.occurrence.min and candidate.occurrence.min > 0 then
                local cnt = occurrence_counts[candidate] or 0
                if cnt < candidate.occurrence.min then
                  error(string.format("Ordered grammar error: expected '%s' before '%s' on command '%s'",
                    candidate.names and candidate.names[1] or candidate.name or candidate.result_key,
                    opt_name, current_node.name))
                end
              end
            end
            if not matched_ord_idx then
              error(string.format("Ordered grammar error: declaration '%s' appeared out of order on command '%s'",
                opt_name, current_node.name))
            end
            ordered_cursor[active_segment] = matched_ord_idx
          end

          if decl.kind == "flag" then
            if attached_val ~= nil then
              error(string.format("Flag '%s' does not take a value", opt_name))
            end
            note_occurrence(decl)
            collected_values[decl] = true

            -- Record in the owner node's segment
            local owner_seg = (decl.owner and route_segment_by_name[decl.owner]) or active_segment
            owner_seg.args[decl.result_key] = true
            i = i + 1

          elseif decl.kind == "option" and decl.form then
            local raw_fields, next_i, matched_captures = form.match(decl.form, argv, i, form_offset or #opt_name + 1)
            if not raw_fields then error(string.format("Option '%s' does not match its declared form", opt_name)) end
            local record = {}
            local function validate_form()
              for key, atom in pairs(matched_captures) do
                local ok, value = adapter.adapt_and_validate(raw_fields[key], atom.schema, key)
                if not ok then error("Validation failed for form capture '" .. atom.key .. "'") end
                record[key] = value
              end
            end
            validate_form()
            note_occurrence(decl)
            if not collected_values[decl] then collected_values[decl] = {} end
            table.insert(collected_values[decl], record)
            local owner_seg = (decl.owner and route_segment_by_name[decl.owner]) or active_segment
            owner_seg.args[decl.result_key] = decl.aggregate == "array" and collected_values[decl] or record
            i = next_i

          elseif decl.kind == "option" then
            local raw_val
            if attached_val ~= nil then
              raw_val = named.normalize_attached_value(attached_val, decl)
              i = i + 1
            else
              if not decl.separator_policy or not decl.separator_policy.detached then
                error(string.format("Option '%s' does not accept a detached value", opt_name))
              end
              i = i + 1
              if i > #argv or argv[i] == "--" then
                error(string.format("Option '%s' requires a value", opt_name))
              end
              raw_val = named.normalize_attached_value(argv[i], decl)
              i = i + 1
            end

            -- Lexical adaptation & validation
            local ok, val_or_issues = adapter.adapt_and_validate(raw_val, decl.schema, decl.result_key)
            if not ok then
              local msg = "Validation failed for option '" .. opt_name .. "': "
              if type(val_or_issues) == "table" and val_or_issues[1] then
                msg = msg .. util.format_issue(val_or_issues[1])
              else
                msg = msg .. tostring(val_or_issues)
              end
              error(msg)
            end

            note_occurrence(decl)
            if not collected_values[decl] then
              collected_values[decl] = {}
            end
            table.insert(collected_values[decl], val_or_issues)

            local owner_seg = (decl.owner and route_segment_by_name[decl.owner]) or active_segment
            if decl.aggregate == "array" then
              owner_seg.args[decl.result_key] = collected_values[decl]
            else
              owner_seg.args[decl.result_key] = val_or_issues
            end
          end

        else
          -- Section 3: Check short flag clusters with transactional atomicity
          local is_cluster = false
          if current_node.short_clusters and token:match("^%-[a-zA-Z0-9]+$") and not token:match("^%-%-") and not attached_separator_pos then
            -- Phase 1: Inspect and validate all cluster characters
            local all_flags = true
            local cluster_decls = {}

            for ch_idx = 2, #token do
              local short_name = "-" .. token:sub(ch_idx, ch_idx)
              local ch_decl = current_node.visible_options_by_name[short_name]
              if ch_decl and ch_decl.kind == "flag" then
                table.insert(cluster_decls, ch_decl)
              else
                all_flags = false
                break
              end
            end

            -- Phase 2: Transactional commit (all-or-nothing)
            if all_flags and #cluster_decls > 0 then
              is_cluster = true
              for _, ch_decl in ipairs(cluster_decls) do
                note_occurrence(ch_decl)
                collected_values[ch_decl] = true
                local owner_seg = (ch_decl.owner and route_segment_by_name[ch_decl.owner]) or active_segment
                owner_seg.args[ch_decl.result_key] = true
              end
              i = i + 1
            end
          end

          if not is_cluster then
            error(string.format("Unknown option or flag '%s' for command '%s'", token, current_node.name))
          end
        end

      else
        -- Non-option token: Child Command Transition or Positional Argument

        -- Section 22: Check child transition vs required positional minimums
        local child_node = routing.edge(current_node, token, options_closed)

        if child_node then
          local missing = routing.first_missing_prefix(current_node, occurrence_counts)
          if missing then
            error(string.format(
              "Missing required argument '%s' before command '%s' on command '%s'",
              missing.name or missing.result_key, token, current_node.name))
          end
          -- Transition to child command!
          current_node = child_node
          active_segment = add_route_segment(current_node)
          i = i + 1
        else
          -- Consume as positional argument on current_node
          local p_idx = positional_cursor[active_segment] or 1
          local matched_arg = nil

          while p_idx <= #current_node.args do
            local candidate = current_node.args[p_idx]
            local cnt = occurrence_counts[candidate] or 0
            local max = candidate.occurrence.max

            if max == nil or cnt < max then
              -- A repeated structured form can be followed by another
              -- positional only when the next token no longer matches its
              -- own lexical shape.  Try transactionally before selecting it.
              if candidate.form and cnt >= (candidate.occurrence.min or 0) then
                local fields = form.match(candidate.form, argv, i)
                if not fields then
                  p_idx = p_idx + 1
                else
                  matched_arg = candidate
                  break
                end
              else
                matched_arg = candidate
                break
              end
            else
              p_idx = p_idx + 1
            end
          end

          if not matched_arg then
            error(string.format("Unexpected positional argument '%s' for command '%s'", token, current_node.name))
          end

          -- Check ordered mode constraint
          if current_node.mode == "ordered" then
            local ord_cur = ordered_cursor[active_segment] or 1
            local decls_order = current_node.declarations_order or {}
            local matched_ord_idx = nil
            for d_idx = ord_cur, #decls_order do
              local candidate = decls_order[d_idx]
              if candidate == matched_arg then
                matched_ord_idx = d_idx
                break
              elseif candidate.occurrence and candidate.occurrence.min and candidate.occurrence.min > 0 then
                local cnt = occurrence_counts[candidate] or 0
                if cnt < candidate.occurrence.min then
                  error(string.format("Ordered grammar error: expected '%s' before '%s' on command '%s'",
                    candidate.names and candidate.names[1] or candidate.name or candidate.result_key,
                    token, current_node.name))
                end
              end
            end
            if not matched_ord_idx then
              error(string.format("Ordered grammar error: argument '%s' appeared out of order on command '%s'",
                token, current_node.name))
            end
            ordered_cursor[active_segment] = matched_ord_idx
          end

          if matched_arg.form then
            local raw_fields, next_i, matched_captures = form.match(matched_arg.form, argv, i)
            if not raw_fields then
              error(string.format("Argument '%s' does not match its declared form", matched_arg.result_key))
            end
            local record = {}
            local function validate_form()
              for key, atom in pairs(matched_captures) do
                local ok, value = adapter.adapt_and_validate(raw_fields[key], atom.schema, key)
                if not ok then error("Validation failed for form capture '" .. atom.key .. "'") end
                record[key] = value
              end
            end
            validate_form()
            note_occurrence(matched_arg)
            if not collected_values[matched_arg] then collected_values[matched_arg] = {} end
            table.insert(collected_values[matched_arg], record)
            active_segment.args[matched_arg.result_key] = matched_arg.aggregate == "array" and collected_values[matched_arg] or record
            i = next_i - 1
          else
            -- Lexical adaptation & validation
            local ok, val_or_issues = adapter.adapt_and_validate(token, matched_arg.schema, matched_arg.result_key)
            if not ok then
              local msg = "Validation failed for argument '" .. matched_arg.name .. "': "
              if type(val_or_issues) == "table" and val_or_issues[1] then
                msg = msg .. util.format_issue(val_or_issues[1])
              else
                msg = msg .. tostring(val_or_issues)
              end
              error(msg)
            end

            note_occurrence(matched_arg)
            if not collected_values[matched_arg] then
              collected_values[matched_arg] = {}
            end
            table.insert(collected_values[matched_arg], val_or_issues)

            if matched_arg.aggregate == "array" then
              active_segment.args[matched_arg.result_key] = collected_values[matched_arg]
            else
              active_segment.args[matched_arg.result_key] = val_or_issues
            end
          end

          positionals_consumed[active_segment] = (positionals_consumed[active_segment] or 0) + 1

          -- If positional has finite max and is saturated, advance cursor
          local cnt = occurrence_counts[matched_arg]
          if matched_arg.occurrence.max ~= nil and cnt >= matched_arg.occurrence.max then
            positional_cursor[active_segment] = p_idx + 1
          else
            positional_cursor[active_segment] = p_idx
          end

          if options_closed then
            local has_unmet_pos = false
            for _, arg_decl in ipairs(current_node.args) do
              local c_cnt = occurrence_counts[arg_decl] or 0
              local min = arg_decl.occurrence.min or 1
              if c_cnt < min then
                has_unmet_pos = true
                break
              end
            end
            if not has_unmet_pos then
              if current_node.end_capture and current_node.end_capture.legacy_passthrough then
                passthrough_active = true
                end_capture = { policy = current_node.end_capture, tokens = passthrough_tokens }
              end
            end
          end

          i = i + 1
        end
      end
    end
  end

  if end_capture and end_capture.policy and end_capture.policy.binding then
    local owner_seg = route_segment_by_name[end_capture.policy.binding.owner] or active_segment
    owner_seg.args[end_capture.policy.binding.result_key] = end_capture.tokens
  end

  -- Handle passthrough tokens (Section 23, Invariant 15)
  if #passthrough_tokens > 0 or passthrough_active then
    if current_node.passthrough_key then
      active_segment.args[current_node.passthrough_key] = passthrough_tokens
    end
  end

  -- Validate occurrence minima for all nodes in the route
  for _, seg in ipairs(route) do
    local node_ir = seg.node_ir

    -- Check required positionals
      for _, arg in ipairs(node_ir.args) do
      local cnt = occurrence_counts[arg] or 0
      local min = arg.occurrence.min or 1
        if cnt < min then
          local name = arg.name or (arg.composed_pattern and arg.composed_pattern.display) or arg.result_key
          error(string.format("Missing required argument '%s' for command '%s'", name, seg.node))
      end
    end

    -- Check required options
    for _, opt in ipairs(node_ir.options) do
      local cnt = occurrence_counts[opt] or 0
      local min = opt.occurrence.min or 0
      if cnt < min then
        error(string.format("Missing required option '%s' for command '%s'",
          opt.names[1] or opt.result_key, seg.node))
      end
    end

    -- Ensure flag defaults: Section 14: absent flags are false
    for _, flag in ipairs(node_ir.flags) do
      if seg.args[flag.result_key] == nil then
        seg.args[flag.result_key] = false
      end
    end
  end

  if current_node.children and next(current_node.children) ~= nil and not current_node.handler then
    error(string.format("Missing command for router node '%s'", current_node.name))
  end

  -- Also populate default false for inherited flags on root/active segments if not set
  for _, seg in ipairs(route) do
    for _, flag in ipairs(seg.node_ir.flags) do
      if seg.args[flag.result_key] == nil then
        seg.args[flag.result_key] = false
      end
    end
  end

  -- Compose combined ctx.args (Section 24)
  local composed_args = {}
  for _, seg in ipairs(route) do
    for k, v in pairs(seg.args) do
      composed_args[k] = v
    end
  end

  -- Add dual-access (foo_bar <-> foo-bar)
  local dual_args = util.create_args_table(composed_args)

  -- Clean public route segments (Section 24: { { node = "root", args = {...} }, ... })
  local public_route = {}
  for _, seg in ipairs(route) do
    table.insert(public_route, {
      node = seg.node,
      node_ir = seg.node_ir,
      args = util.create_args_table(seg.args),
    })
  end

  return {
    target_node = current_node,
    route = public_route,
    args = dual_args,
    passthrough = passthrough_tokens,
  }
end

return M
