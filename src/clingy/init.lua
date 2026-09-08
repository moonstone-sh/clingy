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
c.capture = dsl.capture
c.literal = dsl.literal
c.sequence = dsl.sequence
c.choice = dsl.choice
c.next_token = dsl.next_token

c.optional = dsl.optional

-- Parser modes and capabilities
c.interspersed = dsl.interspersed
c.leading = dsl.leading
c.ordered = dsl.ordered
c.short_clusters = dsl.short_clusters

-- Passthrough
c.passthrough = dsl.passthrough
c.tail = dsl.tail
c["end"] = dsl.tail -- Deprecated compatibility alias; use c.tail.
c.forward = dsl.forward

-- Handlers and signals
c.run = dsl.run
c.signals = dsl.signals
c.signal = dsl.signal
c.stage = dsl.stage

-- Completion
c.complete = dsl.complete
c.values = dsl.values
c.path = dsl.path
c.file = dsl.file
c.directory = dsl.directory
c.dynamic = dsl.dynamic
c.none = dsl.none

-- Submodules & Presentation
c.help = require("clingy.help").format_help
c.format_version = require("clingy.help").format_version
c.scope = require("clingy.scope")
c.process = require("clingy.process")
c.presentation = require("clingy.presentation")
c.composer = setmetatable({}, {
  __index = require("clingy.presentation.composer"),
  __call = function(_, opts)
    return require("clingy.presentation.composer").create_composer(opts)
  end,
})
c.null_host = require("clingy.presentation").create_null_host
c.recording_host = require("clingy.presentation").create_recording_host
c.failing_host = require("clingy.presentation").create_failing_host
c.events = require("clingy.events")
c.lifecycle = require("clingy.lifecycle")
c.compiler = require("clingy.compiler")
c.parser = require("clingy.parser")
c.adapter = require("clingy.adapter")
c.schema_adapter = c.adapter.register
c.completion = require("clingy.completion")
c.util = require("clingy.util")
c.Context = require("clingy.context").Context

c.c = c

return c
