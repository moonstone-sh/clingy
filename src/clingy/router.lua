-- Builds the runtime lookup tables from a command graph
-- (clingy.command-graph.v0). Kept apart from the compiler so a built CLI
-- (clingy.runtime) can compile its router without loading the DSL
-- normalizer.
local util = require("clingy.util")

local M = {}

---Compiles a normalized Command Graph into an optimized runtime CompiledRouter.
---@param graph table ClingyCommandGraph
---@return table CompiledRouter
function M.compile(graph)
  local nodes = graph.nodes
  local bindings = graph.bindings

  local compiled_nodes = {}

  local function build_compiled_node(node_id, inherited_ctx)
    local node = nodes[node_id]
    if not node then return nil end

    local visible_bindings_by_name = {}
    -- Inherited options from ancestors
    for name, b in pairs(inherited_ctx.options) do
      visible_bindings_by_name[name] = b
    end

    local positionals = {}
    local options = {}
    local flags = {}
    local ordered_bindings = {}
    local effective_end_capture = inherited_ctx.end_capture
    if node.end_capture then
      effective_end_capture = node.end_capture
    end

    for _, b_id in ipairs(node.declaration_order) do
      local b = bindings[b_id]
      if b then
        table.insert(ordered_bindings, b)
        if b.kind == "arg" then
          table.insert(positionals, b)
        elseif b.kind == "option" then
          table.insert(options, b)
          for _, name in ipairs(b.names or {}) do
            visible_bindings_by_name[name] = b
          end
        elseif b.kind == "flag" then
          table.insert(flags, b)
          for _, name in ipairs(b.names or {}) do
            visible_bindings_by_name[name] = b
          end
        end
      end
    end

    -- Effective parser policy
    local effective_mode = node.parser_policy.ordering or inherited_ctx.mode or "interspersed"
    local effective_short_clusters
    if node.parser_policy.short_clusters ~= nil and node.parser_policy.short_clusters then
      effective_short_clusters = true
    else
      effective_short_clusters = inherited_ctx.short_clusters or false
    end

    -- Prepare child inherited context
    local next_options = util.shallow_copy(inherited_ctx.options)
    for _, b_id in ipairs(node.bindings) do
      local b = bindings[b_id]
      if b and b.visibility == "descendants" then
        for _, name in ipairs(b.names or {}) do
          next_options[name] = b
        end
      end
    end

    local next_mode = inherited_ctx.mode
    if node.parser_policy.ordering_inherited then
      next_mode = node.parser_policy.ordering
    end

    local next_short_clusters = inherited_ctx.short_clusters
    if node.parser_policy.short_clusters_inherited then
      next_short_clusters = true
    end

    -- End markers follow the same explicit inheritance rule as bindings: a
    -- local end declaration controls only this segment unless wrapped in
    -- c.inherit(...).
    local next_end_capture = inherited_ctx.end_capture
    if node.end_capture and node.end_capture.inherited then
      next_end_capture = node.end_capture
    end

    local child_inherited_ctx = {
      options = next_options,
      mode = next_mode,
      short_clusters = next_short_clusters,
      end_capture = next_end_capture,
    }

    local children = {}
    local child_edges = {}
    for _, child_name in ipairs(node.child_order) do
      local child_id = node.id .. "." .. child_name
      local child = build_compiled_node(child_id, child_inherited_ctx)
      children[child_name] = child
      child_edges[child_name] = child
      for _, alias in ipairs(child.aliases or {}) do
        child_edges[alias] = child
      end
    end

    local compiled_node = {
      id = node.id,
      name = node.name,
      raw_node = node,
      args = positionals,
      options = options,
      flags = flags,
      visible_options_by_name = visible_bindings_by_name,
      inherited_options_by_name = inherited_ctx.options,
      children = children,
      child_edges = child_edges,
      child_names_map = node.children,
      aliases = node.aliases,
      mode = effective_mode,
      short_clusters = effective_short_clusters,
      passthrough_key = node.passthrough_key,
      end_capture = effective_end_capture,
      handler = node.handler,
      signals = node.signals,
      stages = node.stages or {},
      declarations_order = ordered_bindings,
      decl_map = node.decl_map or {},
      metadata = node.metadata,
    }

    compiled_nodes[node_id] = compiled_node
    return compiled_node
  end

  local root_compiled = build_compiled_node(graph.root, {
    options = {},
    mode = "interspersed",
    short_clusters = false,
    end_capture = nil,
  })

  return {
    format = "clingy.compiled-router.v0",
    name = graph.name,
    version = graph.version,
    description = graph.description,
    graph = graph,
    root = root_compiled,
    nodes = compiled_nodes,
  }
end

return M
