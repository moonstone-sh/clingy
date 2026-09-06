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
  return self._graph.graph or self._graph
end

---Generates formatted help text for a target node or subcommand path.
---@param node_or_path any Optional subcommand name, path table, or node
---@return string Formatted help text
function App:help(node_or_path)
  local help_mod = require("clingy.help")
  local target_node = self._graph.root
  local path_segs = {}

  if type(node_or_path) == "string" then
    if self._graph.root.children and self._graph.root.children[node_or_path] then
      target_node = self._graph.root.children[node_or_path]
      table.insert(path_segs, node_or_path)
    end
  elseif type(node_or_path) == "table" then
    if node_or_path.name and node_or_path.visible_options_by_name then
      target_node = node_or_path
    elseif #node_or_path > 0 then
      local cur = self._graph.root
      for _, seg_name in ipairs(node_or_path) do
        if cur.children and cur.children[seg_name] then
          cur = cur.children[seg_name]
          table.insert(path_segs, seg_name)
        end
      end
      target_node = cur
    end
  end

  return help_mod.format_help(self, target_node, path_segs)
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
---@param opts table? Optional overrides: { presentation = ..., composer = ..., composer_mode = "...", stdout = ..., stderr = ... }
---@return integer Exit code (0 for success, non-zero for error)
function App:run(argv, opts)
  argv = argv or (type(arg) == "table" and arg or {})
  opts = opts or {}

  -- Hidden Silent Endpoint for shell completion
  if argv[1] == "--__clingy-complete" then
    local shell = argv[2] or "bash"
    local cword = nil
    local words = {}

    local i = 3
    while i <= #argv do
      local token = argv[i]
      if token:match("^%-%-cword=(%d+)$") then
        cword = tonumber(token:match("^%-%-cword=(%d+)$"))
      elseif token == "--cword" and argv[i + 1] then
        i = i + 1
        cword = tonumber(argv[i])
      else
        table.insert(words, token)
      end
      i = i + 1
    end

    cword = cword or #words

    local comp_mod = require("clingy.completion")
    local ok, resp = pcall(comp_mod.complete, self, { words = words, cword = cword })
    if ok and resp then
      local ok_render, output = pcall(comp_mod.render, resp, shell)
      if ok_render and output and output ~= "" then
        local out_stream = opts.stdout or io.stdout
        out_stream:write(output .. "\n")
      end
    end
    return 0
  end

  -- 1. Resolve Presentation Host (HOST-INV-01, HOST-INV-02, HOST-INV-03, Critique Amendment 5)
  local host = opts.presentation or opts.composer or self._config.presentation
  local is_default_composer = false

  if not host then
    is_default_composer = true
    local mode = opts.composer_mode
    if not mode then
      -- Inspect bootstrap flags from raw argv if present
      for _, arg_token in ipairs(argv) do
        if arg_token == "--json" then
          mode = "json"
          break
        elseif arg_token == "--plain" then
          mode = "plain"
          break
        elseif arg_token == "--quiet" then
          mode = "quiet"
          break
        end
      end
    end
    mode = mode or self._config.mode or "auto"

    host = composer_mod.create_composer({
      mode = mode,
      stdout = opts.stdout,
      stderr = opts.stderr,
      is_tty = opts.is_tty,
      capture = opts.capture,
    })
  elseif opts.composer_mode and host.mode then
    host.mode = (opts.composer_mode == "json") and "ndjson" or opts.composer_mode
  end

  local bus = events.create_bus()

  -- 2. Subscribe Presentation Host to Event Bus with crash isolation (HOST-INV-04, Amendment 3)
  bus:on_any(function(evt)
    pcall(function()
      if host.handle_event then
        host:handle_event(evt)
      end
    end)
  end)

  -- 3. Structured Scope Lifetime for Presentation Host (HOST-INV-06)
  local scope_mod = require("clingy.scope")
  local root_scope = scope_mod.create_scope()
  root_scope:defer(function()
    pcall(function()
      if host.flush then host:flush() end
    end)
    pcall(function()
      if host.close then host:close() end
    end)
  end)

  -- 4. Host Start Demarcation prior to Parsing (HOST-INV-07, Amendment 1)
  if host.start then
    local ok_start, start_err = pcall(function()
      host:start({
        invocation_id = bus.invocation_id,
        app_name = self._graph.name,
        version = self._graph.version,
        argv = argv,
      })
    end)
    if not ok_start then
      bus:emit("diagnostic", {
        type = "diagnostic",
        message = "Fatal presentation initialization error: " .. tostring(start_err),
        exit_code = 1,
      })
      pcall(function()
        if host.finish then
          host:finish({
            status = "failed",
            exit_code = 1,
            error = start_err,
          })
        end
      end)
      root_scope:unwind("error", start_err)
      return 1
    end
  end

  -- 5. Parse argv
  local ok_parse, parsed_or_err = pcall(parser.parse, self._graph, argv)

  if not ok_parse then
    bus:emit("diagnostic", {
      type = "diagnostic",
      message = tostring(parsed_or_err),
      exit_code = 1,
    })
    pcall(function()
      if host.finish then
        host:finish({
          status = "failed",
          exit_code = 1,
          error = parsed_or_err,
        })
      end
    end)
    root_scope:unwind("error", parsed_or_err)
    return 1
  end

  local parsed = parsed_or_err
  local target_node = parsed.target_node

  -- If using default composer without explicit mode, adapt to parsed flags
  if is_default_composer and host.mode and not opts.composer_mode then
    local args = parsed.args or {}
    if args.json then
      host.mode = "ndjson"
    elseif args.plain then
      host.mode = "plain"
    elseif args.quiet then
      host.mode = "quiet"
    end
  end

  local ctx = context_mod.create_context({
    args = parsed.args,
    route = parsed.route,
    passthrough = parsed.passthrough,
    target_node = target_node,
    bus = bus,
    presentation = host,
    composer = host, -- backward-compatibility alias
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
      local status = c._failed and "failed" or "ok"
      local exit_code = c._failed and (c._exit_code ~= 0 and c._exit_code or 1) or 0
      c.bus:emit("invocation_finish", {
        exit_code = exit_code,
        status = status,
      })
      pcall(function()
        if host.finish then
          host:finish({
            status = status,
            exit_code = exit_code,
            error = execute_err,
          })
        end
      end)
    end,
  }

  local ok_dag, dag_err = pcall(function()
    dag:execute(ctx, stage_runners)
  end)

  root_scope:unwind(ok_dag and not ctx._failed and "success" or "error", dag_err)

  if not ok_dag or ctx._failed then
    return ctx._exit_code ~= 0 and ctx._exit_code or 1
  end

  return 0
end

---Handles an incoming signal for this app instance.
function App:handle_signal(sig, ctx)
  return signals.dispatch(sig, ctx, ctx and ctx.target_node or self._graph.root, ctx and ctx.route or {})
end

---Executes completion query against the application router.
---@param req { words?: string[], cword?: integer }|string[]
---@return table CompletionResponse
function App:complete(req)
  local comp_mod = require("clingy.completion")
  return comp_mod.complete(self, req)
end

---Generates shell completion integration script.
---@param shell string "bash"|"zsh"|"fish"|"powershell"
---@param cmd_path? string
---@return string
function App:completion_script(shell, cmd_path)
  local comp_mod = require("clingy.completion")
  return comp_mod.completion_script(self, shell, cmd_path)
end

M.App = App

function M.create_app(graph, config)
  return App.new(graph, config)
end

return M
