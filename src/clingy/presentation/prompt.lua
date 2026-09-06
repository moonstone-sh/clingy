local M = {}

---Computes deterministic non-interactive fallback for prompt requests (Critique Amendment 4).
---@param request { type: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }
---@return any
function M.fallback(request)
  request = request or {}
  local ptype = request.type or "confirm"

  if ptype == "confirm" then
    if request.default ~= nil then
      return request.default
    end
    return false
  elseif ptype == "text" then
    if request.default ~= nil then
      return request.default
    end
    error("Cannot prompt for text in non-interactive mode without a default value")
  end

  return request.default
end

---Standard interactive terminal prompt implementation.
---@param request { type: "confirm"|"text", prompt: string, default?: any, timeout_ms?: integer }
---@param out_sink any
---@param is_tty boolean
---@return any
function M.terminal_prompt(request, out_sink, is_tty)
  request = request or {}
  if not is_tty then
    return M.fallback(request)
  end

  local ptype = request.type or "confirm"

  if ptype == "confirm" then
    local default_val = request.default ~= nil and request.default or false
    local hint = default_val and "[Y/n]" or "[y/N]"

    if out_sink then
      pcall(function()
        out_sink:write(request.prompt .. " " .. hint .. " ")
        out_sink:flush()
      end)
    end

    local line = io.read("*l")
    if not line or line == "" then
      return default_val
    end

    line = line:lower():match("^%s*(.-)%s*$")
    if line == "y" or line == "yes" then
      return true
    elseif line == "n" or line == "no" then
      return false
    end

    return default_val

  elseif ptype == "text" then
    local hint = request.default and (" [" .. tostring(request.default) .. "]: ") or ": "
    if out_sink then
      pcall(function()
        out_sink:write(request.prompt .. hint)
        out_sink:flush()
      end)
    end

    local line = io.read("*l")
    if not line or line == "" then
      if request.default ~= nil then
        return request.default
      end
      return ""
    end

    return line:match("^%s*(.-)%s*$")
  end

  return M.fallback(request)
end

return M
