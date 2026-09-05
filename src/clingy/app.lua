local parser = require("clingy.parser")
local events = require("clingy.events")
local composer_mod = require("clingy.composer")
local context_mod = require("clingy.context")
local lifecycle = require("clingy.lifecycle")
local signals = require("clingy.signals")

local M = {}

local App = {}
App.__index = App

function App.new(graph, config)
  local self = setmetatable({}, App)
  self._graph = graph
  self._config = config or {}
  return self
end

function App:graph()
  return self._graph
end

---Parses argv without executing handlers. Returns parsed context data or raises error.
---@param argv table? Array of arguments (defaults to global arg)
---@return table Parsed result { route = ..., args = ..., passthrough = ..., target_node = ... }
function App:parse(argv)
  argv = argv or (type(arg) == "table" and arg or {})
  return parser.parse(self._graph, argv)
end

---Executes the full CLI lifecycle against the provided argv.
---@param argv table? Array of arguments
---@param opts table? Optional overrides: { composer_mode = "...", stdout = ..., stderr = ... }
---@return integer Exit code (0 for success, non-zero for error)
function App:run(argv, opts)
  argv = argv or (type(arg) == "table" and arg or {})
  opts = opts or {}

  local bus = events.create_bus()

  -- Step 1: Parse argv
  local ok_parse, parsed_or_err = pcall(parser.parse, self._graph, argv)

  -- Determine presentation mode
  local mode = opts.composer_mode
  if not mode and ok_parse then
    local args = parsed_or_err.args or {}
    if args.json then
      mode = "json"
    elseif args.plain then
      mode = "plain"
    elseif args.quiet then
      mode = "quiet"
    end
  end
  mode = mode or self._config.mode or "auto"

  local composer = composer_mod.create_composer({
    mode = mode,
    stdout = opts.stdout,
    stderr = opts.stderr,
    is_tty = opts.is_tty,
    capture = opts.capture,
  })
  composer:attach(bus)

  if not ok_parse then
    bus:emit("diagnostic", {
      type = "diagnostic",
      message = tostring(parsed_or_err),
      exit_code = 1,
    })
    return 1
  end

  local parsed = parsed_or_err
  local target_node = parsed.target_node

  local ctx = context_mod.create_context({
    args = parsed.args,
    route = parsed.route,
    passthrough = parsed.passthrough,
    target_node = target_node,
    bus = bus,
    composer = composer,
    app = self,
  })

  -- Build Lifecycle DAG
  local dag = lifecycle.create_dag()

  -- Add any custom stages declared on nodes along the route
  for _, seg in ipairs(parsed.route) do
    if seg.node_ir and seg.node_ir.stages then
      for _, st in ipairs(seg.node_ir.stages) do
        dag:add_stage(st)
      end
    end
  end

  local stage_runners = {
    bootstrap = function(c)
      c.bus:emit("invocation_start", {
        app_name = self._graph.name,
        version = self._graph.version,
        target_command = target_node.name,
      })
    end,

    run = function(c)
      if target_node.handler then
        local res = target_node.handler(c)
        if res ~= nil and not c._failed then
          c:result(res)
        end
      end
    end,

    finalize = function(c, execute_err)
      if execute_err then
        c:fail(tostring(execute_err), 1)
      end
      c.bus:emit("invocation_finish", {
        exit_code = c._failed and c._exit_code or 0,
        status = c._failed and "failed" or "ok",
      })
    end,
  }

  local ok_dag, dag_err = pcall(function()
    dag:execute(ctx, stage_runners)
  end)

  if not ok_dag or ctx._failed then
    return ctx._exit_code ~= 0 and ctx._exit_code or 1
  end

  return 0
end

---Handles an incoming signal for this app instance.
function App:handle_signal(sig, ctx)
  return signals.dispatch(sig, ctx, ctx and ctx.target_node or self._graph.root, ctx and ctx.route or {})
end

M.App = App

function M.create_app(graph, config)
  return App.new(graph, config)
end

return M
