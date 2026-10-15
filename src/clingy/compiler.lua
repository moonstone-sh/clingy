local util = require("clingy.util")
local discovery = require("clingy.completion.discovery")
local router_compiler = require("clingy.router")

local M = {}

---Copies a declaration so normalization can annotate it, while keeping the
---identity of values the declaration only refers to: schemas (anything with
---a metatable or a `~standard` interface) and functions. Cloning a schema
---made the graph hold copies nothing else could recognize.
local function copy_declaration(value, seen)
  if type(value) ~= "table" or getmetatable(value) ~= nil or value["~standard"] ~= nil then
    return value
  end
  if seen[value] then return seen[value] end
  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[copy_declaration(k, seen)] = copy_declaration(v, seen)
  end
  return copy
end

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
        local copy = copy_declaration(item, {})
        copy._orig_decl = item
        if inherited_flag then
          copy.inherited = true
          copy.visibility = "descendants"
        else
          copy.visibility = copy.visibility or "local"
        end
        table.insert(result, copy)
      end
    end
  end

  return result
end

---Normalizes AST tree into a canonical, frozen ClingyCommandGraph IR.
---@param config table Root configuration table from c.create
---@return table ClingyCommandGraph
function M.normalize(config)
  if type(config) ~= "table" then
    error("c.create requires a configuration table")
  end

  if config[1] ~= nil then
    error("c.create: declarations do not belong directly on the app; use root = c.node({ ... })")
  end

  local root_ast = config.root
  if type(root_ast) ~= "table" or root_ast._tag ~= "node" then
    error("c.create: root must be a c.node({ ... })")
  end

  local nodes = {}
  local bindings = {}

  local function process_node_ast(node_ast, node_name, parent_id)
    local node_id = parent_id and (parent_id .. "." .. node_name) or node_name
    local flattened = flatten_declarations(node_ast.declarations or {}, false)

    local node_binding_ids = {}
    local declaration_order_ids = {}
    local decl_map = {}
    local ordering_mode = nil
    local ordering_mode_inherited = false
    local short_clusters = false
    local short_clusters_inherited = false
    local passthrough_key = nil
    local end_capture = nil
    local handler = nil
    local signals = nil
    local stages = {}

    local pos_index = 1
    for decl_idx, decl in ipairs(flattened) do
      if decl._tag == "declaration" then
        local binding_id = node_id .. ":" .. (decl.result_key or decl.name or tostring(decl_idx))
        local visibility = decl.inherited and "descendants" or "local"

        local comp_meta = nil
        if decl.completion then
          comp_meta = decl.completion._tag == "completion_provider"
            and { origin = decl.completion.kind == "none" and "none" or "explicit", provider = decl.completion }
            or decl.completion
        elseif decl.schema then
          local discovered = discovery.discover_provider(decl.schema)
          if discovered then
            comp_meta = { origin = "schema", provider = discovered }
          end
        end

        local separator_policy = nil
        if decl.kind == "option" then
          local declared = decl.separator_policy
          local attached = {}
          local detached = false
          for _, separator in ipairs((declared and declared.separators) or { "=", " " }) do
            if separator == " " then
              detached = true
            else
              table.insert(attached, separator)
            end
          end
          separator_policy = {
            attached = attached,
            detached = detached,
            trim = not declared or declared.trim ~= false,
          }
        elseif decl.kind == "flag" then
          -- Flags recognize attached separators only to reject an attempted
          -- value; they never consume one.
          separator_policy = { attached = { "=" }, detached = false, trim = true }
        end

        local binding = {
          id = binding_id,
          owner = node_id,
          kind = decl.kind,
          name = decl.name,
          names = decl.names,
          result_key = decl.result_key,
          visibility = visibility,
          position = decl.kind == "arg" and pos_index or nil,
          schema = decl.schema,
          form = decl.form,
          completion = comp_meta,
          occurrence = decl.occurrence or { min = 0, max = 1 },
          values = decl.values or { min = 1, max = 1 },
          aggregate = decl.aggregate or "scalar",
          default = decl.default,
          metadata = decl.metadata,
          separator_policy = separator_policy,
          declaration_index = decl_idx,
        }

        if decl.kind == "arg" then
          pos_index = pos_index + 1
        end

        bindings[binding_id] = binding
        table.insert(node_binding_ids, binding_id)
        table.insert(declaration_order_ids, binding_id)

        decl_map[decl] = binding
        if decl._orig_decl then
          decl_map[decl._orig_decl] = binding
          if decl._orig_decl._inner then
            decl_map[decl._orig_decl._inner] = binding
          end
        end
        if decl._inner then
          decl_map[decl._inner] = binding
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
        if end_capture and not end_capture.legacy_passthrough then
          error(string.format("Compilation Error: Multiple end declarations on node '%s'", node_name))
        end
        passthrough_key = decl.key
        local binding_id = node_id .. ":--passthrough"
        local binding = {
          id = binding_id,
          owner = node_id,
          kind = "passthrough",
          name = "--",
          result_key = passthrough_key,
          visibility = decl.inherited and "descendants" or "local",
          occurrence = { min = 0, max = 1 },
          values = { min = 0, max = nil },
          aggregate = "array",
          declaration_index = decl_idx,
        }
        bindings[binding_id] = binding
        table.insert(node_binding_ids, binding_id)
        table.insert(declaration_order_ids, binding_id)
        end_capture = {
          binding = binding,
          terminator = "--",
          forward = "trimmed",
          inherited = decl.inherited or false,
          legacy_passthrough = true,
        }

      elseif decl._tag == "end" then
        if end_capture then
          error(string.format("Compilation Error: Multiple end declarations on node '%s'", node_name))
        end
        local binding_id = node_id .. ":end:" .. decl.result_key
        local binding = {
          id = binding_id,
          owner = node_id,
          kind = "end",
          name = decl.terminator,
          result_key = decl.result_key,
          visibility = decl.inherited and "descendants" or "local",
          occurrence = { min = 0, max = 1 },
          values = { min = 0, max = nil },
          aggregate = "array",
          declaration_index = decl_idx,
        }
        bindings[binding_id] = binding
        table.insert(node_binding_ids, binding_id)
        table.insert(declaration_order_ids, binding_id)
        end_capture = {
          binding = binding,
          terminator = decl.terminator,
          forward = decl.forward,
          inherited = decl.inherited or false,
          legacy_passthrough = false,
        }

      elseif decl._tag == "run" then
        handler = decl.handler

      elseif decl._tag == "signals" then
        signals = decl.handlers

      elseif decl._tag == "stage" then
        table.insert(stages, decl.stage)
      end
    end

    -- Process children deterministically
    local child_keys = {}
    for k in pairs(node_ast.children or {}) do
      table.insert(child_keys, k)
    end
    table.sort(child_keys)

    local children_map = {}
    local child_order = {}

    for _, child_name in ipairs(child_keys) do
      local child_node_ast = node_ast.children[child_name]
      local child_node_id = node_id .. "." .. child_name
      children_map[child_name] = child_name
      table.insert(child_order, child_name)

      -- Register aliases to primary child name
      local aliases = (child_node_ast.metadata and child_node_ast.metadata.aliases) or {}
      for _, alias in ipairs(aliases) do
        children_map[alias] = child_name
      end

      process_node_ast(child_node_ast, child_name, node_id)
    end

    local command_node = {
      id = node_id,
      name = node_name,
      parent = parent_id,
      aliases = (node_ast.metadata and node_ast.metadata.aliases) or {},
      children = children_map,
      child_order = child_order,
      bindings = node_binding_ids,
      declaration_order = declaration_order_ids,
      parser_policy = {
        ordering = ordering_mode or "interspersed",
        ordering_inherited = ordering_mode_inherited,
        short_clusters = short_clusters,
        short_clusters_inherited = short_clusters_inherited,
      },
      handler = handler,
      signals = signals,
      stages = stages,
      passthrough_key = passthrough_key,
      end_capture = end_capture,
      decl_map = decl_map,
      metadata = node_ast.metadata or {},
    }

    nodes[node_id] = command_node
  end

  process_node_ast(root_ast, "root", nil)

  return {
    format = "clingy.command-graph.v0",
    name = config.name or "cli",
    version = config.version or "0.0.0",
    description = config.description,
    root = "root",
    nodes = nodes,
    bindings = bindings,
  }
end

---Validates the Command Graph for structural ambiguities, collisions, and invariant violations.
---@param graph table ClingyCommandGraph
function M.validate_graph(graph)
  local nodes = graph.nodes
  local bindings = graph.bindings

  -- Traverse from root down every route to validate collision & inheritance invariants
  local function validate_node_recursive(node_id, inherited_scope)
    local node = nodes[node_id]
    if not node then return end

    local local_names = {}
    local local_keys = {}
    local positional_bindings = {}

    -- Check bindings owned by this node
    for _, b_id in ipairs(node.bindings) do
      local b = bindings[b_id]
      if b then
        -- Invariant 13: Positional arguments cannot be inherited
        if b.kind == "arg" and b.visibility == "descendants" then
          error(string.format("Compilation Error: Positional argument '%s' on node '%s' cannot be inherited (Section 16, Invariant 13)", b.name, node.name))
        end

        -- Invariant 13: Cardinality sanity checks
        if b.occurrence then
          local min = b.occurrence.min
          local max = b.occurrence.max
          if min and min < 0 then
            error(string.format("Compilation Error: Impossible cardinality for '%s': min (%d) cannot be negative", b.result_key, min))
          end
          if min and max and min > max then
            error(string.format("Compilation Error: Impossible cardinality for '%s': min (%d) > max (%d)", b.result_key, min, max))
          end
        end

        -- Invariant 12: Output key collision on same node
        local output_keys = { b.result_key }
        for _, output_key in ipairs(output_keys) do
          if local_keys[output_key] then
            error(string.format("Compilation Error: Output-key collision on node '%s' for key '%s'", node.name, output_key))
          end
          -- Invariant 12: Output key collision along route
          if inherited_scope.keys[output_key] then
            error(string.format("Compilation Error: Output-key collision along route to node '%s' for key '%s'", node.name, output_key))
          end
          local_keys[output_key] = b
        end

        if b.kind == "arg" then
          table.insert(positional_bindings, b)
        elseif b.kind == "option" or b.kind == "flag" then
          for _, name in ipairs(b.names or {}) do
            -- Invariant 12: Duplicate option/flag alias on same node
            if local_names[name] then
              error(string.format("Compilation Error: Duplicate option/flag alias '%s' on node '%s'", name, node.name))
            end
            local_names[name] = b

            -- Invariant 12: Child node shadowing inherited option/flag
            if inherited_scope.options[name] then
              error(string.format("Compilation Error: Child node '%s' shadows inherited option/flag '%s' (Invariant 12)", node.name, name))
            end
          end
        end

      end
    end

    -- Invariant 13: Non-final repeated positionals
    for i = 1, #positional_bindings - 1 do
        if positional_bindings[i].occurrence.max == nil and not positional_bindings[i].form then
        error(string.format("Compilation Error: Non-final repeated positional '%s' followed by positional '%s' on node '%s' (Invariant 13)",
          positional_bindings[i].name, positional_bindings[i + 1].name, node.name))
      end
    end

    -- A command edge is a reserved word at this node.  Positionals before
    -- that edge must therefore be a fixed required prefix: otherwise a word
    -- could be both data and a child command, leaving parsing and completion
    -- to guess differently.
    if #node.child_order > 0 then
      for _, positional in ipairs(positional_bindings) do
        local occurrence = positional.occurrence or {}
        if occurrence.min ~= 1 or occurrence.max ~= 1 then
          error(string.format(
            "Compilation Error: Node '%s' has child commands, so positional '%s' must occur exactly once before routing",
            node.name, positional.name))
        end
      end
    end

    -- Child name and alias collision checks
    local child_names_map = {}
    for _, child_name in ipairs(node.child_order) do
      if child_names_map[child_name] then
        error(string.format("Compilation Error: Duplicate command name or alias '%s' on parent '%s'", child_name, node.name))
      end
      child_names_map[child_name] = child_name

      local child_id = node.id .. "." .. child_name
      local child_node = nodes[child_id]
      if child_node then
        for _, alias in ipairs(child_node.aliases or {}) do
          if child_names_map[alias] then
            error(string.format("Compilation Error: Duplicate command alias '%s' on parent '%s' (conflicts with '%s')",
              alias, node.name, child_names_map[alias]))
          end
          child_names_map[alias] = child_name
        end
      end
    end

    -- Compute next inherited scope for children
    local next_options = util.shallow_copy(inherited_scope.options)
    local next_keys = util.shallow_copy(inherited_scope.keys)

    for _, b_id in ipairs(node.bindings) do
      local b = bindings[b_id]
      if b and b.visibility == "descendants" then
        for _, name in ipairs(b.names or {}) do
          next_options[name] = b
        end
      end
      if b then next_keys[b.result_key] = b end
    end

    for _, child_name in ipairs(node.child_order) do
      local child_id = node.id .. "." .. child_name
      validate_node_recursive(child_id, {
        options = next_options,
        keys = next_keys,
      })
    end
  end

  validate_node_recursive(graph.root, { options = {}, keys = {} })
end

---Compiles a normalized Command Graph into an optimized runtime CompiledRouter.
---@param graph table ClingyCommandGraph
---@return table CompiledRouter
M.compile_router = router_compiler.compile

---High-level compile function: normalizes, validates, and builds router.
---@param config table
---@return table Compiled router & graph container
function M.compile(config)
  local graph = M.normalize(config)
  M.validate_graph(graph)
  local router = M.compile_router(graph)
  -- For backward compatibility with existing test harness
  router.root.graph = graph
  return router
end

return M
