local util = require("clingy.util")

local M = {}

---Flattens declarations, unwrapping c.group and applying c.inherit wrappers.
---@param declarations table Array of declarations from DSL
---@param inherited_flag boolean Whether parent wrapper specified inheritance
---@return table Flattened list of normalized declaration items
local function flatten_declarations(declarations, inherited_flag)
  local result = {}

  for _, item in ipairs(declarations) do
    if type(item) == "table" then
      if item._tag == "group" then
        local sub = flatten_declarations(item.declarations, inherited_flag)
        for _, s in ipairs(sub) do
          table.insert(result, s)
        end
      elseif item._tag == "inherit" then
        local sub = flatten_declarations(item.items, true)
        for _, s in ipairs(sub) do
          table.insert(result, s)
        end
      else
        local copy = util.deep_copy(item)
        if inherited_flag then
          copy.inherited = true
        end
        table.insert(result, copy)
      end
    end
  end

  return result
end

---Compiles a node AST into normalized Command Graph IR.
---@param node_ast table The c.node AST
---@param node_name string Name of the command node ("root" or child name)
---@param inherited_ctx table Context inherited from ancestors
---@return table Compiled node IR
local function compile_node(node_ast, node_name, inherited_ctx)
  inherited_ctx = inherited_ctx or {
    inherited_options = {},
    inherited_keys = {},
    inherited_mode = "interspersed",
    inherited_short_clusters = false,
  }

  local flattened = flatten_declarations(node_ast.declarations or {}, false)

  local args = {}
  local options = {}
  local flags = {}
  local ordering_mode = nil
  local ordering_mode_inherited = false
  local short_clusters = nil
  local short_clusters_inherited = false
  local passthrough_key = nil
  local handler = nil
  local signals = nil
  local stages = {}

  local local_names = {}
  local local_keys = {}

  for _, decl in ipairs(flattened) do
    if decl._tag == "declaration" then
      -- Invariant 13: Invalid inherited positionals
      if decl.kind == "arg" and decl.inherited then
        error(string.format("Compilation Error: Positional argument '%s' on node '%s' cannot be inherited (Section 16, Invariant 13)", decl.name, node_name))
      end

      -- Invariant 13: Cardinality validation
      if decl.occurrence then
        local min = decl.occurrence.min
        local max = decl.occurrence.max
        if min and min < 0 then
          error(string.format("Compilation Error: Impossible cardinality for '%s': min (%d) cannot be negative", decl.result_key, min))
        end
        if min and max and min > max then
          error(string.format("Compilation Error: Impossible cardinality for '%s': min (%d) > max (%d)", decl.result_key, min, max))
        end
      end

      -- Check output-key collisions on same node
      if local_keys[decl.result_key] then
        error(string.format("Compilation Error: Output-key collision on node '%s' for key '%s'", node_name, decl.result_key))
      end
      -- Invariant 12: Check output-key collision along route
      if inherited_ctx.inherited_keys[decl.result_key] then
        error(string.format("Compilation Error: Output-key collision along route to node '%s' for key '%s'", node_name, decl.result_key))
      end
      local_keys[decl.result_key] = decl

      if decl.kind == "arg" then
        decl.owner = node_name
        table.insert(args, decl)
      elseif decl.kind == "option" or decl.kind == "flag" then
        decl.owner = node_name
        -- Check alias collision on same node & shadowing of inherited options
        for _, name in ipairs(decl.names or {}) do
          if local_names[name] then
            error(string.format("Compilation Error: Duplicate option/flag alias '%s' on node '%s'", name, node_name))
          end
          local_names[name] = decl

          -- Invariant 12: Detect child option shadowing an inherited option (NO silent shadowing!)
          if inherited_ctx.inherited_options[name] then
            error(string.format("Compilation Error: Child node '%s' shadows inherited option/flag '%s' (Invariant 12)", node_name, name))
          end
        end

        if decl.kind == "option" then
          table.insert(options, decl)
        else
          table.insert(flags, decl)
        end
      end

    elseif decl._tag == "parser_mode" then
      if ordering_mode and ordering_mode ~= decl.mode then
        error(string.format("Compilation Error: Conflicting parser modes ('%s' vs '%s') declared on node '%s'", ordering_mode, decl.mode, node_name))
      end
      ordering_mode = decl.mode
      ordering_mode_inherited = decl.inherited or false

    elseif decl._tag == "short_clusters" then
      short_clusters = true
      short_clusters_inherited = decl.inherited or false

    elseif decl._tag == "passthrough" then
      if passthrough_key then
        error(string.format("Compilation Error: Multiple passthrough declarations on node '%s'", node_name))
      end
      passthrough_key = decl.key
      if local_keys[passthrough_key] then
        error(string.format("Compilation Error: Output-key collision on node '%s' for passthrough key '%s'", node_name, passthrough_key))
      end
      if inherited_ctx.inherited_keys[passthrough_key] then
        error(string.format("Compilation Error: Output-key collision along route to node '%s' for passthrough key '%s'", node_name, passthrough_key))
      end
      local_keys[passthrough_key] = decl

    elseif decl._tag == "run" then
      handler = decl.handler

    elseif decl._tag == "signals" then
      signals = decl.handlers

    elseif decl._tag == "stage" then
      table.insert(stages, decl.stage)
    end
  end

  -- Invariant 13: Non-final repeated positionals followed by another positional
  for i = 1, #args - 1 do
    if args[i].occurrence.max == nil then
      error(string.format("Compilation Error: Non-final repeated positional '%s' followed by positional '%s' on node '%s' (Invariant 13)",
        args[i].name, args[i + 1].name, node_name))
    end
  end

  -- Resolve effective parser mode for this node
  local effective_mode = ordering_mode or inherited_ctx.inherited_mode or "interspersed"
  local effective_short_clusters
  if short_clusters ~= nil then
    effective_short_clusters = short_clusters
  else
    effective_short_clusters = inherited_ctx.inherited_short_clusters or false
  end

  -- Prepare child inherited context
  local next_inherited_options = util.shallow_copy(inherited_ctx.inherited_options)
  local next_inherited_keys = util.shallow_copy(inherited_ctx.inherited_keys)

  -- Add inherited options from this node
  for _, opt in ipairs(options) do
    if opt.inherited then
      for _, name in ipairs(opt.names) do
        next_inherited_options[name] = opt
      end
    end
  end
  for _, flag in ipairs(flags) do
    if flag.inherited then
      for _, name in ipairs(flag.names) do
        next_inherited_options[name] = flag
      end
    end
  end

  -- Along the route, all keys from this node are reserved
  for k, decl in pairs(local_keys) do
    next_inherited_keys[k] = decl
  end

  local next_inherited_mode = inherited_ctx.inherited_mode
  if ordering_mode_inherited then
    next_inherited_mode = ordering_mode
  end

  local next_inherited_short_clusters = inherited_ctx.inherited_short_clusters
  if short_clusters_inherited then
    next_inherited_short_clusters = true
  end

  local child_inherited_ctx = {
    inherited_options = next_inherited_options,
    inherited_keys = next_inherited_keys,
    inherited_mode = next_inherited_mode,
    inherited_short_clusters = next_inherited_short_clusters,
  }

  -- Validate child command names and aliases for duplicate collisions
  local child_names_map = {}
  local compiled_children = {}

  for child_name, child_node in pairs(node_ast.children or {}) do
    if child_names_map[child_name] then
      error(string.format("Compilation Error: Duplicate command name or alias '%s' on parent '%s'", child_name, node_name))
    end
    child_names_map[child_name] = child_name

    local aliases = (child_node.metadata and child_node.metadata.aliases) or {}
    for _, alias in ipairs(aliases) do
      if child_names_map[alias] then
        error(string.format("Compilation Error: Duplicate command alias '%s' on parent '%s' (conflicts with '%s')",
          alias, node_name, child_names_map[alias]))
      end
      child_names_map[alias] = child_name
    end

    compiled_children[child_name] = compile_node(child_node, child_name, child_inherited_ctx)
  end

  -- Build map of active visible options for this node segment
  -- Local options + inherited options from ancestors
  local visible_options_by_name = {}
  for name, decl in pairs(inherited_ctx.inherited_options) do
    visible_options_by_name[name] = decl
  end
  for _, opt in ipairs(options) do
    for _, name in ipairs(opt.names) do
      visible_options_by_name[name] = opt
    end
  end
  for _, flag in ipairs(flags) do
    for _, name in ipairs(flag.names) do
      visible_options_by_name[name] = flag
    end
  end

  return {
    name = node_name,
    metadata = node_ast.metadata or {},
    args = args,
    options = options,
    flags = flags,
    visible_options_by_name = visible_options_by_name,
    inherited_options_by_name = inherited_ctx.inherited_options,
    children = compiled_children,
    child_names_map = child_names_map,
    mode = effective_mode,
    short_clusters = effective_short_clusters,
    passthrough_key = passthrough_key,
    handler = handler,
    signals = signals,
    stages = stages,
    declarations_order = flattened,
  }
end

---Compiles the configuration passed to c.create into an immutable Command Graph IR.
---@param config table Configuration table containing root node and metadata
---@return table Compiled Command Graph
function M.compile(config)
  if type(config) ~= "table" then
    error("c.create requires a configuration table")
  end

  local root_ast = nil
  if config[1] and type(config[1]) == "table" and config[1]._tag == "root" then
    root_ast = config[1].node
  elseif config.root and type(config.root) == "table" then
    if config.root._tag == "root" then
      root_ast = config.root.node
    elseif config.root._tag == "node" then
      root_ast = config.root
    end
  end

  if not root_ast then
    error("c.create: root node not specified. Use c.root(c.node({...}))")
  end

  local root_ir = compile_node(root_ast, "root", {
    inherited_options = {},
    inherited_keys = {},
    inherited_mode = "interspersed",
    inherited_short_clusters = false,
  })

  return {
    name = config.name or "cli",
    version = config.version or "0.0.0",
    description = config.description,
    root = root_ir,
  }
end

return M
