local dsl = require("clingy.dsl")
local compiler = require("clingy.compiler")
local app_mod = require("clingy.app")

local c = {}

---Compiles a declarative CLI configuration into an executable CLI App.
---Section 3: local CLI = c.create({ name = "...", version = "...", c.root(c.node({...})) })
---@param config table App configuration with root node and metadata
---@return table Clingy App instance
function c.create(config)
  local graph = compiler.compile(config)
  return app_mod.create_app(graph, config)
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
c.scope = require("clingy.scope")
c.process = require("clingy.process")
c.composer = require("clingy.composer")
c.events = require("clingy.events")
c.lifecycle = require("clingy.lifecycle")
c.compiler = require("clingy.compiler")
c.parser = require("clingy.parser")
c.adapter = require("clingy.adapter")
c.util = require("clingy.util")

return c
