--[[
  Clingy v0 — LuaLS Editor Plugin
  Route-aware context type inference for inline `c.run(function(ctx) ... end)`

  Operates strictly via static source inspection (zero arbitrary code evaluation).
  Safe across LuaLS 2.x and 3.x+.
]]

local M = {}

---Finds the matching closing bracket in Lua code, respecting strings and comments.
local function find_matching_bracket(text, start_pos, open_char, close_char)
  local depth = 0
  local in_str = nil
  local i = start_pos
  local len = #text
  while i <= len do
    local c = text:sub(i, i)
    local c2 = text:sub(i, i + 1)
    if in_str then
      if in_str == "double" and c == "\"" and text:sub(i - 1, i - 1) ~= "\\" then
        in_str = nil
      elseif in_str == "single" and c == "\'" and text:sub(i - 1, i - 1) ~= "\\" then
        in_str = nil
      elseif in_str == "long" and c2 == "]]" then
        in_str = nil
        i = i + 1
      end
    else
      if c == "\"" then
        in_str = "double"
      elseif c == "\'" then
        in_str = "single"
      elseif c2 == "[[" then
        in_str = "long"
        i = i + 1
      elseif c2 == "--" then
        if text:sub(i + 2, i + 3) == "[[" then
          local close_idx = text:find("]]", i + 4, true)
          if close_idx then i = close_idx + 1 else break end
        else
          local nl_idx = text:find("\n", i + 2, true)
          if nl_idx then i = nl_idx else break end
        end
      elseif c == open_char then
        depth = depth + 1
      elseif c == close_char then
        depth = depth - 1
        if depth == 0 then
          return i
        end
      end
    end
    i = i + 1
  end
  return nil
end

---Derives canonical identifier key from option/flag alias names.
local function derive_key(names)
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
      return name:gsub("%-", "_")
    end
  end

  local chosen = longest_long or shortest_short or "arg"
  return chosen:gsub("%-", "_")
end

---Splits an argument list by top-level commas respecting quotes, brackets, and parentheses.
local function split_top_level_args(args_str)
  local parts = {}
  local depth = 0
  local in_str = nil
  local cur = ""
  for i = 1, #args_str do
    local c = args_str:sub(i, i)
    if in_str then
      cur = cur .. c
      if c == in_str and args_str:sub(i - 1, i - 1) ~= "\\" then
        in_str = nil
      end
    elseif c == "\"" or c == "'" then
      in_str = c
      cur = cur .. c
    elseif c == "(" or c == "{" or c == "[" then
      depth = depth + 1
      cur = cur .. c
    elseif c == ")" or c == "}" or c == "]" then
      depth = depth - 1
      cur = cur .. c
    elseif c == "," and depth == 0 then
      local trimmed = cur:match("^%s*(.-)%s*$")
      if trimmed ~= "" then table.insert(parts, trimmed) end
      cur = ""
    else
      cur = cur .. c
    end
  end
  local trimmed = cur:match("^%s*(.-)%s*$")
  if trimmed ~= "" then table.insert(parts, trimmed) end
  return parts
end

---Extracts type O from a type string like:
---standard_schema.Schema<I, O>, valua.BaseSchema<I, O>, StandardSchema<I, O>, StandardSchemaV1<I, O>
local function extract_schema_output_type(type_str)
  if not type_str then return nil end
  local o = type_str:match("[%w_.:]*[sS]chema[%w_.:]*%s*<[^,>]+,%s*([^>]+)>")
  if o then
    return o:match("^%s*(.-)%s*$")
  end
  return nil
end

---Scans doc_text to find all local identifiers bound to schema/validation modules.
local function find_imported_validator_namespaces(doc_text)
  local namespaces = { v = true, valua = true, fixture_schema = true, standard_schema = true }
  for var_name, mod_name in doc_text:gmatch("local%s+([%w_]+)%s*=%s*require%s*%(?%s*[\"']([^\"']+)[\"']%s*%)?") do
    local lower_mod = mod_name:lower()
    if lower_mod:find("valua") or lower_mod:find("schema") or lower_mod:find("validator") or lower_mod:find("zod") or lower_mod:find("type") then
      namespaces[var_name] = true
    end
  end
  return namespaces
end

---Resolves a schema expression or variable name to a concrete LuaCATS type.
---Supports:
---1. Preceding LuaCATS annotations (---@type, ---@return standard_schema.Schema<I, O> or valua.BaseSchema<I, O>)
---2. Schema wrapper/decorator functions (describe, annotate, meta, pipe, optional, default) on validator namespaces
---3. Picklist/Enum literal unions (picklist({ "a", "b" }) -> "a"|"b") on validator namespaces
---4. Well-known primitive schema constructors (string, integer, number, boolean) on validator namespaces
---5. Variable assignment chains (local A = B)
---6. Bare arguments without schema (c.arg("name") -> string)
---7. Clean fallback to "unknown" for unproven/unrecognized constructors (e.g. anything.integer())
---@param schema_expr? string
---@param doc_text string
---@param visited? table<string, boolean>
---@return string
local function resolve_schema_type(schema_expr, doc_text, visited)
  if not schema_expr or schema_expr == "" then
    return "string"
  end

  visited = visited or {}
  schema_expr = schema_expr:match("^%s*(.-)%s*$") or ""
  if schema_expr == "" then
    return "string"
  end

  local valid_ns = find_imported_validator_namespaces(doc_text)

  -- 1. Direct function call with preceding ---@return standard_schema.Schema<I, O> or valua.BaseSchema<I, O>
  local direct_fn_call = schema_expr:match("^([%w_]+)%s*%(")
  if direct_fn_call then
    local ret_annot = doc_text:match("%-%-%-@return%s+([^\r\n]+)[\r\n]+%s*local%s+function%s+" .. direct_fn_call .. "%s*%(")
      or doc_text:match("%-%-%-@return%s+([^\r\n]+)[\r\n]+%s*function%s+" .. direct_fn_call .. "%s*%(")
    if ret_annot then
      local o = extract_schema_output_type(ret_annot)
      if o then return o end
    end
  end

  -- 2. Schema wrapper / decorator methods on validator namespaces: describe, annotate, meta, pipe, optional, default
  -- e.g. v.describe(v.picklist(...), "desc"), v.pipe(v.integer(), ...), v.optional(v.string())
  local prefix_wrap, wrapper_method, inner_args = schema_expr:match("^([%w_]+)%.([%w_]+)%s*%((.*)%)%s*$")
  if prefix_wrap and valid_ns[prefix_wrap] and (wrapper_method == "describe" or wrapper_method == "annotate" or wrapper_method == "meta" or wrapper_method == "pipe" or wrapper_method == "optional" or wrapper_method == "default") then
    local inner_parts = split_top_level_args(inner_args)
    if inner_parts[1] then
      local inner_type = resolve_schema_type(inner_parts[1], doc_text, visited)
      if wrapper_method == "optional" and not inner_type:find("|nil", 1, true) then
        return inner_type .. "|nil"
      end
      return inner_type
    end
  end

  -- 3. Picklist / Enum literal unions on validator namespaces: v.picklist({ "dev", "prod" })
  local prefix_pl, picklist_args = schema_expr:match("^([%w_]+)%.picklist%s*%(%s*(%b{})%s*.*%)")
  if not prefix_pl then
    prefix_pl, picklist_args = schema_expr:match("^([%w_]+)%.enum%s*%(%s*(%b{})%s*.*%)")
  end
  if prefix_pl and valid_ns[prefix_pl] and picklist_args then
    local items = {}
    for str_val in picklist_args:gmatch("[\"']([^\"']+)[\"']") do
      table.insert(items, string.format("%q", str_val))
    end
    for num_val in picklist_args:gmatch("(%d+%.?%d*)") do
      table.insert(items, num_val)
    end
    if #items > 0 then
      return table.concat(items, "|")
    end
  end

  -- 4. Well-known primitive schema constructors on validator namespaces:
  local prefix_prim, prim_method = schema_expr:match("^([%w_]+)%.([%w_]+)%s*%b()")
  if prefix_prim and valid_ns[prefix_prim] then
    if prim_method == "string" then
      return "string"
    elseif prim_method == "integer" or prim_method == "int" then
      return "integer"
    elseif prim_method == "number" or prim_method == "float" then
      return "number"
    elseif prim_method == "boolean" or prim_method == "bool" then
      return "boolean"
    end
  end

  -- 5. Variable identifier tracing: local var_name = ...
  local var_name = schema_expr:match("^([%w_]+)$")
  if var_name and not visited[var_name] then
    visited[var_name] = true

    -- 5a. Check for preceding ---@type standard_schema.Schema<I, O> or valua.BaseSchema<I, O>
    local type_annot = doc_text:match("%-%-%-@type%s+([^\r\n]+)[\r\n]+%s*local%s+" .. var_name .. "%s*=")
    if type_annot then
      local o = extract_schema_output_type(type_annot)
      if o then return o end
    end

    -- 5b. Follow local var_name = <expression> (Variable Assignment Tracing)
    local var_def = doc_text:match("local%s+" .. var_name .. "%s*=%s*([^\r\n]+)")
    if var_def then
      var_def = var_def:gsub("%-%-.*$", ""):match("^%s*(.-)%s*$") or ""
      local fn_call_name = var_def:match("^([%w_]+)%s*%(")
      if fn_call_name then
        local ret_annot = doc_text:match("%-%-%-@return%s+([^\r\n]+)[\r\n]+%s*local%s+function%s+" .. fn_call_name .. "%s*%(")
          or doc_text:match("%-%-%-@return%s+([^\r\n]+)[\r\n]+%s*function%s+" .. fn_call_name .. "%s*%(")
        if ret_annot then
          local o = extract_schema_output_type(ret_annot)
          if o then return o end
        end
      end
      return resolve_schema_type(var_def, doc_text, visited)
    end
  end

  -- Unproven schema: strictly return "unknown"
  return "unknown"
end

---Parses option arguments into list of flag names and resolved type string.
local function parse_option_decl(opt_args, doc_text)
  local parts = split_top_level_args(opt_args)
  local names = {}
  local schema_expr = nil
  for _, part in ipairs(parts) do
    local flag_name = part:match("^[\"'](%-+[%w_%-]+)[\"']$")
    if flag_name then
      table.insert(names, flag_name)
    else
      schema_expr = part
    end
  end
  local t = resolve_schema_type(schema_expr, doc_text)
  return names, t
end

---Parses argument declaration into argument name and resolved type string.
local function parse_arg_decl(arg_args, doc_text)
  local parts = split_top_level_args(arg_args)
  local name = parts[1] and parts[1]:match("^[\"']([%w_%-]+)[\"']$") or "arg"
  local schema_expr = parts[2]
  local t = resolve_schema_type(schema_expr, doc_text)
  return name, t
end

---Parses declarations in a text block, extracting inherited, positional, and local fields.
local function parse_decls_in_block(block_text, doc_text)
  local inherited = {}
  local positionals = {}
  local locals = {}

  -- 1. Inherit blocks
  local i_pos = 1
  while true do
    local s, e = block_text:find("c%.inherit%s*%(", i_pos)
    if not s then break end
    local match_end = find_matching_bracket(block_text, e, "(", ")")
    if match_end then
      local inherit_content = block_text:sub(e + 1, match_end - 1)
      for flag_call in inherit_content:gmatch("c%.flag%b()") do
        local inner = flag_call:match("^c%.flag%s*%((.*)%)%s*$")
        if inner then
          local names = {}
          for name in inner:gmatch("[\"'](%-+[%w_%-]+)[\"']") do
            table.insert(names, name)
          end
          if #names > 0 then
            inherited[derive_key(names)] = "boolean"
          end
        end
      end
      for opt_call in inherit_content:gmatch("c%.option%b()") do
        local inner = opt_call:match("^c%.option%s*%((.*)%)%s*$")
        if inner then
          local names, t = parse_option_decl(inner, doc_text)
          if #names > 0 then
            inherited[derive_key(names)] = t .. "|nil"
          end
        end
      end
      i_pos = match_end + 1
    else
      i_pos = e + 1
    end
  end

  -- Mask out c.inherit blocks
  local masked = block_text:gsub("c%.inherit%s*%b()", "")

  -- 2. Positionals: c.arg(...)
  for arg_call in masked:gmatch("c%.arg%b()") do
    local inner = arg_call:match("^c%.arg%s*%((.*)%)%s*$")
    if inner then
      local arg_name, t = parse_arg_decl(inner, doc_text)
      positionals[arg_name:gsub("%-", "_")] = t
    end
  end

  -- 3. Repeated wrappers
  for rep_call in masked:gmatch("c%.repeated%b()") do
    local rep_inner = rep_call:match("^c%.repeated%s*%((.*)%)%s*$")
    if rep_inner then
      for opt_call in rep_inner:gmatch("c%.option%b()") do
        local inner = opt_call:match("^c%.option%s*%((.*)%)%s*$")
        if inner then
          local names, t = parse_option_decl(inner, doc_text)
          if #names > 0 then
            locals[derive_key(names)] = string.format("(%s)[]|nil", t)
          end
        end
      end
      for arg_call in rep_inner:gmatch("c%.arg%b()") do
        local inner = arg_call:match("^c%.arg%s*%((.*)%)%s*$")
        if inner then
          local name, t = parse_arg_decl(inner, doc_text)
          positionals[name:gsub("%-", "_")] = string.format("(%s)[]", t)
        end
      end
    end
  end

  -- 4. Required wrappers
  for req_call in masked:gmatch("c%.required%b()") do
    local req_inner = req_call:match("^c%.required%s*%((.*)%)%s*$")
    if req_inner then
      for opt_call in req_inner:gmatch("c%.option%b()") do
        local inner = opt_call:match("^c%.option%s*%((.*)%)%s*$")
        if inner then
          local names, t = parse_option_decl(inner, doc_text)
          if #names > 0 then
            locals[derive_key(names)] = t
          end
        end
      end
      for arg_call in req_inner:gmatch("c%.arg%b()") do
        local inner = arg_call:match("^c%.arg%s*%((.*)%)%s*$")
        if inner then
          local name, t = parse_arg_decl(inner, doc_text)
          positionals[name:gsub("%-", "_")] = t
        end
      end
    end
  end

  local unrepeated = masked:gsub("c%.repeated%s*%b()", ""):gsub("c%.required%s*%b()", "")

  -- 5. Local flags
  for flag_call in unrepeated:gmatch("c%.flag%b()") do
    local inner = flag_call:match("^c%.flag%s*%((.*)%)%s*$")
    if inner then
      local names = {}
      for name in inner:gmatch("[\"'](%-+[%w_%-]+)[\"']") do
        table.insert(names, name)
      end
      if #names > 0 then
        locals[derive_key(names)] = "boolean"
      end
    end
  end

  -- 6. Local options
  for opt_call in unrepeated:gmatch("c%.option%b()") do
    local inner = opt_call:match("^c%.option%s*%((.*)%)%s*$")
    if inner then
      local names, t = parse_option_decl(inner, doc_text)
      if #names > 0 then
        locals[derive_key(names)] = t .. "|nil"
      end
    end
  end

  -- 7. Passthrough
  for pt_call in unrepeated:gmatch("c%.passthrough%b()") do
    local key = pt_call:match("c%.passthrough%s*%(%s*[\"']([%w_%-]+)[\"']%s*%)")
    if key then
      locals[key:gsub("%-", "_")] = "string[]"
    end
  end

  return inherited, positionals, locals
end

---Statically extracts declared fields from a block of Clingy node DSL text.
---@param node_text string
---@return table<string, string> fields map of name -> type string
function M.extract_node_fields(node_text)
  local inh, pos, loc = parse_decls_in_block(node_text, node_text)
  local fields = {}
  for k, v in pairs(loc) do fields[k] = v end
  for k, v in pairs(pos) do fields[k] = v end
  for k, v in pairs(inh) do fields[k] = v end
  return fields
end

---Parses the full hierarchical c.node tree within a document.
local function parse_node_tree(doc_text)
  local nodes = {}
  local idx = 1
  while true do
    local s, e = doc_text:find("c%.node%s*%(", idx)
    if not s then break end
    local match_end = find_matching_bracket(doc_text, e, "(", ")")
    if match_end then
      local node_content = doc_text:sub(e + 1, match_end - 1)
      local node_rec = {
        start_idx = s,
        end_idx = match_end,
        content = node_content,
        children = {},
        parent = nil,
      }
      table.insert(nodes, node_rec)
      idx = s + 1
    else
      idx = e + 1
    end
  end

  -- Determine nesting (parent-child) using monotonic stack
  local stack = {}
  for _, node in ipairs(nodes) do
    while #stack > 0 and stack[#stack].end_idx < node.end_idx do
      table.remove(stack)
    end
    if #stack > 0 and stack[#stack].start_idx < node.start_idx and stack[#stack].end_idx > node.end_idx then
      local parent = stack[#stack]
      node.parent = parent
      table.insert(parent.children, node)
    end
    table.insert(stack, node)
  end

  -- For each node, extract local declarations masking out child node ranges
  for _, node in ipairs(nodes) do
    local direct_content = node.content
    for _, child in ipairs(node.children) do
      local rel_start = child.start_idx - (node.start_idx + 7)
      local rel_end = child.end_idx - (node.start_idx + 7)
      if rel_start >= 1 and rel_end <= #direct_content then
        direct_content = direct_content:sub(1, rel_start - 1) .. string.rep(" ", rel_end - rel_start + 1) .. direct_content:sub(rel_end + 1)
      end
    end

    local inh, pos, loc = parse_decls_in_block(direct_content, doc_text)
    node.inherited = inh
    node.positionals = pos
    node.locals = loc
  end

  return nodes
end

---Builds a LuaCATS Context type annotation string for the given fields map.
---@param fields table<string, string>
---@return string
function M.build_context_annotation(fields)
  local field_defs = {}
  local keys = {}
  for k in pairs(fields) do
    table.insert(keys, k)
  end
  table.sort(keys)

  for _, k in ipairs(keys) do
    table.insert(field_defs, string.format("%s: %s", k, fields[k]))
  end

  local args_shape = "{" .. table.concat(field_defs, ", ") .. "}"
  return string.format("clingy.Context<%s>", args_shape)
end

---Computes the effective visible fields for a specific node in the tree.
local function compute_visible_fields(node)
  local visible = {}
  -- 1. All locals, positionals, and inherited from self
  for k, v in pairs(node.locals) do visible[k] = v end
  for k, v in pairs(node.positionals) do visible[k] = v end
  for k, v in pairs(node.inherited) do visible[k] = v end

  -- 2. Inherited & positionals from all ancestor nodes
  local p = node.parent
  while p do
    for k, v in pairs(p.inherited) do visible[k] = v end
    for k, v in pairs(p.positionals) do visible[k] = v end
    p = p.parent
  end

  return visible
end

---Processes document text for LuaLS, injecting route-specific context annotations for each `c.run`.
---@param uri string
---@param text string
---@return string?
function M.process_text(uri, text)
  if not text or not text:find("c%.run") then
    return text
  end

  local ok, res = pcall(function()
    local nodes = parse_node_tree(text)

    -- If no c.node hierarchy found, check if document is a modular leaf (e.g. returns table of args or requires args)
    if #nodes == 0 then
      local inh, pos, loc = parse_decls_in_block(text, text)
      local fallback_fields = {}
      for k, v in pairs(loc) do fallback_fields[k] = v end
      for k, v in pairs(pos) do fallback_fields[k] = v end
      for k, v in pairs(inh) do fallback_fields[k] = v end

      -- If still empty and uri is given, check for sibling args.lua
      if next(fallback_fields) == nil and uri and uri ~= "" then
        local dir = uri:match("^(.*[/\\])[^/\\]+$")
        if dir then
          local args_path = dir:gsub("^file://", "") .. "args.lua"
          local f = io.open(args_path, "r")
          if f then
            local args_text = f:read("*a")
            f:close()
            local a_inh, a_pos, a_loc = parse_decls_in_block(args_text, args_text)
            for k, v in pairs(a_loc) do fallback_fields[k] = v end
            for k, v in pairs(a_pos) do fallback_fields[k] = v end
            for k, v in pairs(a_inh) do fallback_fields[k] = v end
          end
        end
      end

      if next(fallback_fields) == nil then
        return text
      end

      local ctx_type = M.build_context_annotation(fallback_fields)
      return text:gsub("(c%.run%s*%(%s*function%s*%(%s*([%w_]+)%s*%))", function(full_call, param_name)
        return string.format("%s ---@cast %s %s", full_call, param_name, ctx_type)
      end)
    end

    -- For each c.run occurrence, find the innermost enclosing node and inject cast
    local result_text = ""
    local last_pos = 1

    local scan_pos = 1
    while true do
      local s, e, param_name = text:find("c%.run%s*%(%s*function%s*%(%s*([%w_]+)%s*%)", scan_pos)
      if not s then break end

      -- Find innermost enclosing node for position `s`
      local innermost = nil
      for _, node in ipairs(nodes) do
        if s >= node.start_idx and s <= node.end_idx then
          if not innermost or (node.start_idx > innermost.start_idx and node.end_idx < innermost.end_idx) then
            innermost = node
          end
        end
      end

      local fields = innermost and compute_visible_fields(innermost) or {}
      local injection = ""
      if next(fields) ~= nil then
        local ctx_type = M.build_context_annotation(fields)
        injection = string.format(" ---@cast %s %s", param_name, ctx_type)
      end

      result_text = result_text .. text:sub(last_pos, e) .. injection
      last_pos = e + 1
      scan_pos = e + 1
    end

    result_text = result_text .. text:sub(last_pos)
    return result_text
  end)

  if ok and res then
    return res
  end
  return text
end

-- Hook for LuaLS OnSetText
function OnSetText(uri, text)
  return M.process_text(uri, text)
end

-- Hook for LuaLS OnTransformAst (if present in environment)
function OnTransformAst(uri, ast)
  return ast
end

return M
