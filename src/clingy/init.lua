local dsl = require("clingy.dsl")
local compiler = require("clingy.compiler")
local app_mod = require("clingy.app")

local c = {}

---Compiles a declarative CLI configuration into an executable CLI App.
---Section 3: local CLI = c.create({ name = "...", version = "...", c.root(c.node({...})) })
---@param config table App configuration with root node and metadata
---@return table Clingy App instance
function c.create(config)
  local compiled = compiler.compile(config)
  return app_mod.create_app(compiled, config)
end

---Reflects the normalized ClingyCommandGraph (clingy.command-graph.v0) from an App or config.
---@param target table App instance or config table
---@return table ClingyCommandGraph
function c.reflect(target)
  if type(target) == "table" and target.graph and type(target.graph) == "function" then
    return target:graph()
  elseif type(target) == "table" and target.format == "clingy.command-graph.v0" then
    return target
  elseif type(target) == "table" and target._graph then
    return target._graph.graph or target._graph
  end
  return compiler.normalize(target)
end

---Inspects the root node of the Command Graph.
---@param target table App instance or config table
---@return table ClingyCommandNode
function c.inspect(target)
  local g = c.reflect(target)
  return g.nodes[g.root]
end

-- DSL constructors
c.root = dsl.root
c.node = dsl.node
c.group = dsl.group
c.inherit = dsl.inherit

-- Argument declarations
c.arg = dsl.arg
c.option = dsl.option
c.flag = dsl.flag

-- Cardinality modifiers
c.optional = dsl.optional
c.required = dsl.required
c.repeated = dsl.repeated

-- Parser modes and capabilities
c.interspersed = dsl.interspersed
c.leading = dsl.leading
c.ordered = dsl.ordered
c.short_clusters = dsl.short_clusters

-- Passthrough
c.passthrough = dsl.passthrough

-- Handlers and signals
c.run = dsl.run
c.signals = dsl.signals
c.signal = dsl.signal
c.stage = dsl.stage

-- Submodules
c.help = require("clingy.help").format_help
c.format_version = require("clingy.help").format_version
c.scope = require("clingy.scope")
c.process = require("clingy.process")
c.composer = require("clingy.composer")
c.events = require("clingy.events")
c.lifecycle = require("clingy.lifecycle")
c.compiler = require("clingy.compiler")
c.parser = require("clingy.parser")
c.adapter = require("clingy.adapter")
c.schema_adapter = c.adapter.register
c.util = require("clingy.util")
c.Context = require("clingy.context").Context

c.c = c

return c
