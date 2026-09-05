local adapter = require("clingy.adapter")

local M = {}

---Formats the usage line for a command node.
---@param app table Clingy application
---@param node table Compiled node or Node IR
---@param path_segments string[] Path segments (e.g. {"init", "instant"})
---@return string Usage line
local function format_usage(app, node, path_segments)
  local parts = { app._graph.name or "cli" }
  for _, seg in ipairs(path_segments or {}) do
    table.insert(parts, seg)
  end

  local has_options = (node.options and #node.options > 0) or (node.flags and #node.flags > 0) or (node.inherited_options_by_name and next(node.inherited_options_by_name) ~= nil)
  if has_options then
    table.insert(parts, "[OPTIONS]")
  end

  if node.args and #node.args > 0 then
    for _, arg in ipairs(node.args) do
      local name = arg.name:upper()
      if arg.occurrence and arg.occurrence.max == nil then
        name = "<" .. name .. "...>"
      elseif arg.occurrence and arg.occurrence.min == 0 then
        name = "[" .. name .. "]"
      else
        name = "<" .. name .. ">"
      end
      table.insert(parts, name)
    end
  end

  if node.children and next(node.children) ~= nil then
    table.insert(parts, "[COMMAND]")
  end

  if node.passthrough_key then
    table.insert(parts, "[-- <ARGS...>]")
  end

  return table.concat(parts, " ")
end

---Formats help text for a specific command node.
---@param app table Clingy application
---@param node table Compiled node
---@param path_segments string[]? Array of string segment names
---@return string Formatted help text
function M.format_help(app, node, path_segments)
  node = node or (app._graph and app._graph.root)
  path_segments = path_segments or {}

  local lines = {}

  -- Title & Description
  local desc = (node.metadata and node.metadata.description) or (node == app._graph.root and app._graph.description)
  if desc and #desc > 0 then
    table.insert(lines, desc)
    table.insert(lines, "")
  end

  -- Usage
  table.insert(lines, "Usage:")
  table.insert(lines, "  " .. format_usage(app, node, path_segments))
  table.insert(lines, "")

  -- Positional Arguments
  if node.args and #node.args > 0 then
    table.insert(lines, "Arguments:")
    for _, arg in ipairs(node.args) do
      local schema_info = adapter.inspect_schema(arg.schema)
      local name_col = string.format("  <%s>", arg.name:upper())
      local desc_parts = {}

      local doc_desc = (arg.metadata and arg.metadata.description) or schema_info.description
      if doc_desc then
        table.insert(desc_parts, doc_desc)
      end

      if schema_info.options then
        table.insert(desc_parts, "[" .. table.concat(schema_info.options, "|") .. "]")
      end

      local def_val = arg.default ~= nil and arg.default or schema_info.default
      if def_val ~= nil then
        table.insert(desc_parts, string.format("(default: %s)", tostring(def_val)))
      end

      local desc_str = table.concat(desc_parts, " ")
      if #desc_str > 0 then
        table.insert(lines, string.format("%-24s %s", name_col, desc_str))
      else
        table.insert(lines, name_col)
      end
    end
    table.insert(lines, "")
  end

  -- Local Options
  local local_decls = {}
  for _, opt in ipairs(node.options or {}) do table.insert(local_decls, opt) end
  for _, flg in ipairs(node.flags or {}) do table.insert(local_decls, flg) end

  if #local_decls > 0 then
    table.insert(lines, "Options:")
    for _, decl in ipairs(local_decls) do
      local names_str = table.concat(decl.names or { decl.name }, ", ")
      local schema_info = adapter.inspect_schema(decl.schema)

      if decl.kind == "option" then
        names_str = names_str .. " <VALUE>"
      end

      local desc_parts = {}
      local doc_desc = (decl.metadata and decl.metadata.description) or schema_info.description
      if doc_desc then
        table.insert(desc_parts, doc_desc)
      end

      if schema_info.options then
        table.insert(desc_parts, "[" .. table.concat(schema_info.options, "|") .. "]")
      end

      local def_val = decl.default ~= nil and decl.default or schema_info.default
      if def_val ~= nil then
        table.insert(desc_parts, string.format("(default: %s)", tostring(def_val)))
      end

      local desc_str = table.concat(desc_parts, " ")
      local col_str = string.format("  %-22s", names_str)
      if #desc_str > 0 then
        table.insert(lines, string.format("%s %s", col_str, desc_str))
      else
        table.insert(lines, col_str)
      end
    end
    table.insert(lines, "")
  end

  -- Global / Inherited Options (Section 31: Distinguishable from local options)
  local inherited_decls = {}
  local seen_inherited = {}
  for _, b in pairs(node.inherited_options_by_name or {}) do
    if not seen_inherited[b.id] then
      seen_inherited[b.id] = true
      table.insert(inherited_decls, b)
    end
  end

  if #inherited_decls > 0 then
    table.insert(lines, "Global Options:")
    for _, decl in ipairs(inherited_decls) do
      local names_str = table.concat(decl.names or { decl.name }, ", ")
      local schema_info = adapter.inspect_schema(decl.schema)

      if decl.kind == "option" then
        names_str = names_str .. " <VALUE>"
      end

      local desc_parts = {}
      local doc_desc = (decl.metadata and decl.metadata.description) or schema_info.description
      if doc_desc then
        table.insert(desc_parts, doc_desc)
      end

      local owner_tag = string.format("[inherited from %s]", decl.owner or "root")
      table.insert(desc_parts, owner_tag)

      local desc_str = table.concat(desc_parts, " ")
      local col_str = string.format("  %-22s", names_str)
      table.insert(lines, string.format("%s %s", col_str, desc_str))
    end
    table.insert(lines, "")
  end

  -- Subcommands
  if node.children and next(node.children) ~= nil then
    table.insert(lines, "Commands:")
    local child_names = {}
    for k in pairs(node.children) do
      table.insert(child_names, k)
    end
    table.sort(child_names)

    for _, c_name in ipairs(child_names) do
      local child = node.children[c_name]
      local c_desc = (child.metadata and child.metadata.description) or ""
      local aliases_str = ""
      if child.aliases and #child.aliases > 0 then
        aliases_str = " (aliases: " .. table.concat(child.aliases, ", ") .. ")"
      end
      table.insert(lines, string.format("  %-22s %s%s", c_name, c_desc, aliases_str))
    end
    table.insert(lines, "")
  end

  return table.concat(lines, "\n")
end

---Formats version information for an application.
---@param app table Clingy application
---@return string Formatted version string
function M.format_version(app)
  local name = app._graph.name or "cli"
  local ver = app._graph.version or "0.0.0"
  return string.format("%s %s", name, ver)
end

return M
