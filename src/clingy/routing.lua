-- Shared command-edge semantics for execution and completion.
--
-- A node's positional declarations are an exact required prefix when it has
-- children.  Child names and aliases are reserved after that prefix; `--`
-- closes routing so a reserved spelling can be passed as ordinary data.
local M = {}

function M.first_missing_prefix(node, occurrence_counts)
  for _, declaration in ipairs(node.args or {}) do
    local count = occurrence_counts[declaration] or 0
    local minimum = (declaration.occurrence and declaration.occurrence.min) or 1
    if count < minimum then
      return declaration
    end
  end
  return nil
end

function M.prefix_complete(node, occurrence_counts)
  return M.first_missing_prefix(node, occurrence_counts) == nil
end

function M.edge(node, token, routing_closed)
  if routing_closed then return nil end
  return node.child_edges and node.child_edges[token] or nil
end

return M
