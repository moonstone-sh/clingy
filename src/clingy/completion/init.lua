--[[
  src/clingy/completion/init.lua
  Clingy Completion Subsystem Facade.
]]

local response = require("clingy.completion.response")
local context_mod = require("clingy.completion.context")
local providers = require("clingy.completion.providers")
local discovery = require("clingy.completion.discovery")
local partial_parser = require("clingy.completion.partial_parser")

local backends = {
  bash = require("clingy.completion.backends.bash"),
  zsh = require("clingy.completion.backends.zsh"),
  fish = require("clingy.completion.backends.fish"),
  powershell = require("clingy.completion.backends.powershell"),
  pwsh = require("clingy.completion.backends.powershell"),
}

local M = {
  response = response,
  context = context_mod,
  providers = providers,
  discovery = discovery,
  partial_parser = partial_parser,
  backends = backends,
}

---Executes completion query against the router for given words/cword.
---@param app_or_router table
---@param req table|string[] Table with { words = string[], cword = integer } or raw words
---@return table CompletionResponse
function M.complete(app_or_router, req)
  local words = {}
  local cword = nil

  if type(req) == "table" and req.words then
    words = req.words
    cword = req.cword
  elseif type(req) == "table" then
    words = req
    cword = #words
  end

  local router = app_or_router._graph or app_or_router
  local parsed = partial_parser.parse_partial(router, words, cword)
  local resp = partial_parser.resolve_candidates(parsed)
  return resp
end

---Renders a completion response for a target shell.
---@param resp table CompletionResponse
---@param shell string "bash"|"zsh"|"fish"|"powershell"
---@return string
function M.render(resp, shell)
  local backend = backends[shell] or backends.bash
  return backend.render(resp)
end

---Generates completion integration script for target shell.
---@param app_or_router table
---@param shell string "bash"|"zsh"|"fish"|"powershell"
---@param cmd_path? string
---@return string
function M.completion_script(app_or_router, shell, cmd_path)
  local app_name = "cli"
  if type(app_or_router) == "string" then
    app_name = app_or_router
  elseif type(app_or_router) == "table" then
    app_name = app_or_router.name or (app_or_router._graph and app_or_router._graph.name) or "cli"
  end
  local backend = backends[shell]
  if not backend then
    error(string.format("Unsupported completion shell '%s'. Supported: bash, zsh, fish, powershell", tostring(shell)))
  end
  return backend.script(app_name, cmd_path or app_name)
end

return M
