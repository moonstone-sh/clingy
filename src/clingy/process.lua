local util = require("clingy.util")

local M = {}

---Build an exec-able Bash supervisor for a headless child process group.
---Use a launcher to exec the script so it receives terminal signals directly.
function M.supervisor_script(opts)
  return require("clingy.supervisor").script(opts)
end

local VALID_STATES = {
  declared = 1,
  spawning = 2,
  running = 3,
  draining = 4,
  terminating = 5,
  killed = 6,
  reaped = 7,
}

local ManagedProcess = {}
ManagedProcess.__index = ManagedProcess

function ManagedProcess.new(opts, ctx)
  opts = opts or {}
  local self = setmetatable({}, ManagedProcess)
  self.argv = opts.argv or {}
  self.cwd = opts.cwd
  self.env = opts.env
  self.mode = opts.mode or "capture" -- "capture" | "inherit" | "interactive" | "protocol"
  self.ctx = ctx
  self.pid = opts.pid or "proc-" .. tostring(math.random(10000, 99999))
  self._state = "declared"
  self.exit_code = nil
  self.stdout_buffer = ""
  self.stderr_buffer = ""

  -- Invariant 22: Control IPC channel isolation
  self.ipc_inbox = {}
  self.ipc_outbox = {}
  self.ipc_listeners = {}

  return self
end

function ManagedProcess:state()
  return self._state
end

function ManagedProcess:set_state(new_state)
  if not VALID_STATES[new_state] then
    error(string.format("Invalid process state: %s", tostring(new_state)))
  end
  self._state = new_state
end

---Sends a structured message over the isolated control IPC channel.
---Invariant 22: Control IPC is separate from stdout/stderr.
function ManagedProcess:send_ipc(msg)
  table.insert(self.ipc_outbox, msg)
  if self.ctx and self.ctx.bus then
    self.ctx.bus:emit("process_ipc_send", {
      process_id = self.pid,
      message = msg,
    })
  end
end

---Receives a message from the control IPC channel.
function ManagedProcess:recv_ipc()
  if #self.ipc_inbox > 0 then
    return table.remove(self.ipc_inbox, 1)
  end
  return nil
end

function ManagedProcess:on_ipc(fn)
  table.insert(self.ipc_listeners, fn)
end

function ManagedProcess:push_ipc(msg)
  table.insert(self.ipc_inbox, msg)
  for _, fn in ipairs(self.ipc_listeners) do
    pcall(fn, msg)
  end
end

---Starts execution of the managed process.
function ManagedProcess:start()
  if self._state ~= "declared" then
    error("Process already started (state: " .. self._state .. ")")
  end

  self:set_state("spawning")
  if self.ctx and self.ctx.bus then
    self.ctx.bus:emit("process_start", {
      process_id = self.pid,
      argv = self.argv,
      mode = self.mode,
    })
  end

  self:set_state("running")

  -- Format shell command line
  local cmd_parts = {}
  if self.cwd then
    table.insert(cmd_parts, string.format("cd %q &&", self.cwd))
  end
  if self.env then
    for k, v in pairs(self.env) do
      table.insert(cmd_parts, string.format("%s=%q", k, tostring(v)))
    end
  end
  for _, arg in ipairs(self.argv) do
    table.insert(cmd_parts, string.format("%q", tostring(arg)))
  end
  self._cmd_line = table.concat(cmd_parts, " ")

  return self
end

---Signals the process to drain/terminate gracefully.
function ManagedProcess:terminate()
  if self._state == "running" then
    self:set_state("draining")
    self:set_state("terminating")
  end
end

---Forces termination of the process.
function ManagedProcess:kill(sig)
  if self._state == "running" or self._state == "draining" or self._state == "terminating" then
    self:set_state("killed")
  end
end

---Waits for process completion and reaps the process.
---Core invariant: Clingy retains ownership until process is reaped.
function ManagedProcess:wait()
  if self._state == "declared" then
    self:start()
  end

  if self._state == "reaped" then
    return self.exit_code, self.stdout_buffer, self.stderr_buffer
  end

  local exit_code = 0
  local output = ""

  if self.mode == "capture" or self.mode == "protocol" then
    local handle = io.popen(self._cmd_line .. " 2>&1")
    if handle then
      output = handle:read("*a") or ""
      local ok, exit_type, code = handle:close()
      if ok == true then
        exit_code = 0
      elseif type(exit_type) == "number" then
        exit_code = exit_type
      elseif type(code) == "number" then
        exit_code = code
      else
        exit_code = 1
      end
    end
    self.stdout_buffer = output

    if self.ctx and self.ctx.bus and #output > 0 then
      self.ctx.bus:emit("process_output", {
        process_id = self.pid,
        stream = "stdout",
        data = output,
      })
    end

  elseif self.mode == "inherit" or self.mode == "interactive" then
    local host = self.ctx and self.ctx.presentation
    if self.mode == "interactive" and host and host.suspend then
      local ok_suspend, suspend_err = pcall(function()
        host:suspend({ reason = "subprocess", process = self })
      end)
      if not ok_suspend then
        self.exit_code = 1
        self:set_state("killed")
        if self.ctx and self.ctx.bus then
          self.ctx.bus:emit("diagnostic", {
            type = "diagnostic",
            message = "Failed to suspend Presentation Host before interactive subprocess: " .. tostring(suspend_err),
            exit_code = 1,
          })
        end
        error("Failed to suspend Presentation Host before interactive subprocess: " .. tostring(suspend_err), 2)
      end
    end

    local ok, exit_type, code = pcall(function()
      return os.execute(self._cmd_line)
    end)

    if self.mode == "interactive" and host and host.resume then
      local ok_resume, resume_err = pcall(function()
        host:resume()
      end)
      if not ok_resume and self.ctx and self.ctx.bus then
        self.ctx.bus:emit("diagnostic", {
          type = "diagnostic",
          message = "Presentation Host failed to resume after interactive subprocess: " .. tostring(resume_err),
          level = "error",
        })
      end
    end

    if ok then
      local exec_ok, t_or_c, maybe_code = exit_type, code, nil
      if exec_ok == true then
        exit_code = 0
      elseif type(exec_ok) == "number" then
        exit_code = exec_ok
      elseif type(t_or_c) == "number" then
        exit_code = t_or_c
      else
        exit_code = 1
      end
    else
      exit_code = 1
    end
  end

  self.exit_code = exit_code
  self:set_state("reaped")

  if self.ctx and self.ctx.bus then
    self.ctx.bus:emit("process_exit", {
      process_id = self.pid,
      exit_code = exit_code,
    })
  end

  return exit_code, self.stdout_buffer, self.stderr_buffer
end

M.ManagedProcess = ManagedProcess

function M.spawn(opts, ctx)
  local proc = ManagedProcess.new(opts, ctx)
  proc:start()
  return proc
end

return M
