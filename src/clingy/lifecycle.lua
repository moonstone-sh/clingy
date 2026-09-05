local util = require("clingy.util")

local M = {}

local LifecycleDAG = {}
LifecycleDAG.__index = LifecycleDAG

function LifecycleDAG.new()
  local self = setmetatable({}, LifecycleDAG)
  self.stages = {}
  self:init_default_stages()
  return self
end

function LifecycleDAG:init_default_stages()
  self:add_stage({ id = "bootstrap" })
  self:add_stage({ id = "terminal_detect", after = { "bootstrap" } })
  self:add_stage({ id = "parse", after = { "terminal_detect" } })
  self:add_stage({ id = "route", after = { "parse" } })
  self:add_stage({ id = "validate", after = { "route" } })
  self:add_stage({ id = "prepare", after = { "validate" } })
  self:add_stage({ id = "dispatch", after = { "prepare" } })
  self:add_stage({ id = "run", after = { "dispatch" } })
  self:add_stage({ id = "finalize", after = { "run" } })
end

function LifecycleDAG:add_stage(stage_def)
  if not stage_def or not stage_def.id then
    error("Lifecycle stage definition requires an 'id'")
  end
  -- Replace existing default or add new
  self.stages[stage_def.id] = stage_def
end

---Topologically sorts all registered lifecycle stages.
---@return table Ordered array of stage definitions
function LifecycleDAG:resolve_order()
  local stage_list = {}
  local deps = {}
  local all_stages = {}

  for id, s in pairs(self.stages) do
    deps[id] = {}
    all_stages[id] = s
    table.insert(stage_list, s)
  end

  for _, s in ipairs(stage_list) do
    for _, a in ipairs(s.after or {}) do
      if all_stages[a] then
        deps[s.id][a] = true
      end
    end
    for _, b in ipairs(s.before or {}) do
      if all_stages[b] then
        deps[b][s.id] = true
      end
    end
  end

  local sorted_ids = {}
  local visited = {}
  local temp = {}

  local function visit(id)
    if temp[id] then
      error("Lifecycle DAG error: Cycle detected involving stage '" .. id .. "'")
    end
    if not visited[id] then
      temp[id] = true
      for dep_id in pairs(deps[id]) do
        visit(dep_id)
      end
      temp[id] = false
      visited[id] = true
      table.insert(sorted_ids, id)
    end
  end

  for _, s in ipairs(stage_list) do
    if not visited[s.id] then
      visit(s.id)
    end
  end

  local ordered = {}
  for _, id in ipairs(sorted_ids) do
    table.insert(ordered, all_stages[id])
  end
  return ordered
end

---Executes the lifecycle stages against an execution context.
function LifecycleDAG:execute(ctx, stage_runners)
  stage_runners = stage_runners or {}
  local ordered = self:resolve_order()

  local finalize_stage = self.stages["finalize"]
  local execute_err = nil

  for _, stage in ipairs(ordered) do
    if stage.id ~= "finalize" then
      local runner = stage_runners[stage.id] or stage.run
      if runner then
        local ok, err = pcall(runner, ctx)
        if not ok then
          execute_err = err
          break
        end
      end
    end
  end

  -- Invariant 23: Deterministic finalize / unwind execution
  if finalize_stage then
    local finalize_runner = stage_runners["finalize"] or finalize_stage.run
    if finalize_runner then
      pcall(finalize_runner, ctx, execute_err)
    end
  end

  if execute_err then
    error(execute_err)
  end
end

M.LifecycleDAG = LifecycleDAG

function M.create_dag()
  return LifecycleDAG.new()
end

return M
