local M = {}

local SIGNAL_NORMALIZATION = {
  SIGINT = "interrupt",
  INT = "interrupt",
  interrupt = "interrupt",

  SIGTERM = "terminate",
  TERM = "terminate",
  terminate = "terminate",

  SIGHUP = "hangup",
  HUP = "hangup",
  hangup = "hangup",
}

---Normalizes signal names preserving distinct identity (Invariant 19).
function M.normalize(sig)
  if type(sig) == "number" then
    if sig == 2 then return "interrupt" end
    if sig == 15 then return "terminate" end
    if sig == 1 then return "hangup" end
    return "signal_" .. tostring(sig)
  end
  return SIGNAL_NORMALIZATION[sig] or tostring(sig):lower()
end

---Resolves and dispatches a signal against the hierarchy of registered policies.
---Nearest active policy is consulted first (scope -> target node -> ancestor nodes -> app).
function M.dispatch(raw_sig, ctx, target_node, route)
  local norm_sig = M.normalize(raw_sig)

  local evt = {
    raw_signal = raw_sig,
    signal = norm_sig,
    timestamp = os.time(),
  }

  if ctx then
    ctx._sig_counts = ctx._sig_counts or {}
    ctx._sig_counts[norm_sig] = (ctx._sig_counts[norm_sig] or 0) + 1
    evt.count = ctx._sig_counts[norm_sig]

    if ctx.bus then
      ctx.bus:emit("signal", evt)
    end

    -- Escalation check (Section 19):
    -- If SIGTERM arrives during active SIGINT confirmation/prompt, cancel prompt and force shutdown immediately
    if norm_sig == "terminate" and ctx._prompt_active then
      ctx._prompt_active = false
      if ctx.composer and ctx.composer.cancel_prompt then
        ctx.composer:cancel_prompt()
      end
      return { action = "force_shutdown", reason = "terminate_during_confirmation" }
    end

    -- If a second SIGINT arrives, escalate immediately to force shutdown
    if norm_sig == "interrupt" and evt.count >= 2 then
      return { action = "force_shutdown", reason = "second_sigint" }
    end
  end

  -- 1. Check nearest active node policy first, then ancestors in reverse
  if route and #route > 0 then
    for r_idx = #route, 1, -1 do
      local seg = route[r_idx]
      local node_ir = seg.node_ir
      if node_ir and node_ir.signals and node_ir.signals[norm_sig] then
        local handler = node_ir.signals[norm_sig]
        return handler(ctx, evt)
      end
    end
  end

  if target_node and target_node.signals and target_node.signals[norm_sig] then
    local handler = target_node.signals[norm_sig]
    return handler(ctx, evt)
  end

  -- 2. Default behaviors
  if norm_sig == "interrupt" then
    return { action = "interrupt" }
  elseif norm_sig == "terminate" then
    return { action = "shutdown" }
  end

  return { action = "continue" }
end

return M
