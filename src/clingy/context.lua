local scope_mod = require("clingy.scope")
local process_mod = require("clingy.process")

local M = {}

local Context = {}
Context.__index = Context

function Context.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Context)
  self.args = opts.args or {}
  self.route = opts.route or {}
  self.passthrough = opts.passthrough or {}
  self.target_node = opts.target_node
  self.bus = opts.bus
  self.presentation = opts.presentation or opts.composer
  ---@deprecated Use ctx.presentation instead; ctx.composer is a transitional compatibility alias
  self.composer = self.presentation
  self.app = opts.app
  self._scopes = {}
  self._failed = false
  self._exit_code = 0
  return self
end

---Retrieves a typed argument value by its declaration Binding handle or string key.
---@generic O
---@param binding clingy.Binding<O>|string
---@return O?
function Context:get(binding)
  if type(binding) == "string" then
    return self.args[binding]
  end

  if type(binding) ~= "table" then
    return nil
  end

  -- 1. Check target node declaration map
  if self.target_node and self.target_node.decl_map then
    local b = self.target_node.decl_map[binding]
    if b and b.result_key then
      return self.args[b.result_key]
    end
  end

  -- 2. Check active route segments (from target node back up to root)
  if self.route then
    for i = #self.route, 1, -1 do
      local seg = self.route[i]
      if seg.node_ir and seg.node_ir.decl_map then
        local b = seg.node_ir.decl_map[binding]
        if b and b.result_key then
          return self.args[b.result_key]
        end
      end
    end
  end

  -- 3. Check entire application graph if accessible
  if self.app and self.app._graph then
    local g = self.app._graph.nodes or (self.app._graph.graph and self.app._graph.graph.nodes)
    if g then
      for _, n in pairs(g) do
        if n.decl_map and n.decl_map[binding] then
          local b = n.decl_map[binding]
          if b and b.result_key then
            return self.args[b.result_key]
          end
        end
      end
    end
  end

  return nil
end

---Creates a structured resource scope with deterministic LIFO defer unwind (Section 30, Invariant 23).
function Context:scope(fn)
  local scope = scope_mod.create_scope(nil, self)
  table.insert(self._scopes, scope)

  local ok, res = pcall(fn, scope)
  scope:unwind(ok and "success" or "error", not ok and res or nil)

  if not ok then
    error(res)
  end
  return res
end

---Spawns a managed child subprocess (Section 31, 32, Invariant 18).
function Context:spawn(opts)
  return process_mod.spawn(opts, self)
end

---Creates an execution span for telemetry and events.
function Context:span(name, fn)
  if not self.bus then
    if fn then return fn() end
    return nil
  end

  local span_id = self.bus:start_span(name)
  if fn then
    local ok, res = pcall(fn, span_id)
    self.bus:end_span(span_id, ok and "ok" or "error")
    if not ok then
      error(res)
    end
    return res
  end
  return span_id
end

---Emits a progress event.
function Context:progress(task, percent, msg)
  if self.bus then
    self.bus:emit("progress", {
      task = task,
      percentage = percent,
      message = msg,
    })
  end
end

---Emits a milestone event.
function Context:milestone(msg)
  if self.bus then
    self.bus:emit("milestone", {
      message = msg,
    })
  end
end

---Emits a structured log event.
function Context:log(level, msg, metadata)
  if self.bus then
    self.bus:emit("log", {
      level = level or "info",
      message = msg,
      metadata = metadata,
    })
  end
end

---Emits a result event.
function Context:result(data, msg)
  if self.bus then
    self.bus:emit("result", {
      data = data,
      message = msg,
    })
  end
end

---Marks execution failure.
function Context:fail(msg_or_err, exit_code)
  self._failed = true
  self._exit_code = exit_code or 1
  if self.bus then
    self.bus:emit("diagnostic", {
      message = tostring(msg_or_err),
      exit_code = self._exit_code,
    })
  end
end

---Prompts user for confirmation via PresentationHost (Section 40, HOST-INV-11).
function Context:confirm(prompt, opts)
  opts = opts or {}
  return self:prompt({
    type = "confirm",
    prompt = prompt,
    default = opts.default ~= nil and opts.default or false,
    timeout_ms = opts.timeout_ms,
  })
end

---Sends an interactive prompt request to the PresentationHost.
---@param request { type: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }
---@return any
function Context:prompt(request)
  request = request or {}
  if self.presentation and self.presentation.prompt then
    local ok, res = pcall(function()
      return self.presentation:prompt(request)
    end)
    if ok and res ~= nil then
      return res
    elseif not ok then
      error("Prompt failed in PresentationHost: " .. tostring(res), 2)
    end
  end
  local prompt_mod = require("clingy.presentation.prompt")
  return prompt_mod.fallback(request)
end

M.Context = Context

function M.create_context(opts)
  return Context.new(opts)
end

return M
