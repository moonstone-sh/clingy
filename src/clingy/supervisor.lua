-- Generate an exec-able OS supervisor without requiring Lua signal bindings.
-- This is a foreground, non-interactive child process-group owner for Bash 3.2+.
local M = {}

local function quote(value)
  value = tostring(value)
  assert(not value:find("\0", 1, true), "supervisor arguments cannot contain NUL")
  return "'" .. value:gsub("'", "'\\''") .. "'"
end

function M.script(opts)
  assert(type(opts) == "table" and type(opts.argv) == "table" and #opts.argv > 0,
    "supervisor requires a nonempty argv")
  local grace = opts.grace_ms or 2000
  assert(type(grace) == "number" and grace >= 0 and grace <= 60000,
    "supervisor grace_ms must be between 0 and 60000")
  local header = {
    "#!/usr/bin/env bash\n",
    "label=" .. quote(opts.label or "Clingy") .. "\n",
    "grace_ticks=" .. math.ceil(grace / 100) .. "\n",
    "watch_stdin=" .. (opts.stdin_eof and "1" or "0") .. "\n",
    "lock_dir=" .. quote(opts.lock_dir or "") .. "\n",
    "cleanup_files=(",
  }
  for _, path in ipairs(opts.cleanup_files or {}) do header[#header + 1] = quote(path) .. " " end
  header[#header + 1] = ")\n"
  if opts.cwd then header[#header + 1] = "cd -- " .. quote(opts.cwd) .. " || exit 1\n" end
  local keys = {}
  for key in pairs(opts.env or {}) do
    assert(type(key) == "string" and key:match("^[%a_][%w_]*$"), "invalid supervisor environment key")
    keys[#keys + 1] = key
  end
  table.sort(keys)
  for _, key in ipairs(keys) do
    header[#header + 1] = "export " .. key .. "=" .. quote(opts.env[key]) .. "\n"
  end
  header[#header + 1] = "set --"
  for _, value in ipairs(opts.argv) do header[#header + 1] = " " .. quote(value) end
  header[#header + 1] = "\n"

  return table.concat(header) .. [=[
child_pid=
parent_monitor_pid=
requested_exit=
cleaning=0
have_lock=0
owner_pid=$PPID

signal_group() {
  [ -n "$child_pid" ] && kill -"$1" -- "-$child_pid" 2>/dev/null || true
}

on_signal() {
  if [ -n "$requested_exit" ] || [ "$cleaning" -eq 1 ]; then
    signal_group KILL
  fi
  requested_exit=$1
  # Bash can restart a blocking `read` after a trap whose handler returns.
  # Closing only the supervisor's stdin wakes it without exposing stdin to the
  # headless child.
  exec 0<&-
}

cleanup() {
  [ "$cleaning" -eq 0 ] || return
  cleaning=1
  if [ -n "$parent_monitor_pid" ]; then
    kill -TERM "$parent_monitor_pid" 2>/dev/null || true
    wait "$parent_monitor_pid" 2>/dev/null || true
  fi
  signal_group TERM
  ticks=0
  while [ -n "$child_pid" ] && kill -0 -- "-$child_pid" 2>/dev/null && [ "$ticks" -lt "$grace_ticks" ]; do
    sleep 0.1
    ticks=$((ticks + 1))
  done
  signal_group KILL
  if [ -n "$child_pid" ]; then wait "$child_pid" 2>/dev/null || true; fi
  if [ -z "$lock_dir" ] || [ "$have_lock" -eq 1 ]; then
    for path in "${cleanup_files[@]}"; do rm -f -- "$path"; done
  fi
  if [ "$have_lock" -eq 1 ]; then
    rm -f -- "$lock_dir/owner.pid"
    rmdir -- "$lock_dir" 2>/dev/null || true
  fi
}

trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
trap cleanup EXIT

if [ -n "$lock_dir" ]; then
  if ! mkdir -- "$lock_dir" 2>/dev/null; then
    printf '%s\n' "$label: session lock exists: $lock_dir" >&2
    exit 1
  fi
  have_lock=1
  printf '%s\n' "$$" > "$lock_dir/owner.pid"
fi

# Job control gives this child its own process group even without a TTY.
# Only the foreground supervisor reads the terminal; the child runs headless.
set -m
CLINGY_SUPERVISED=1 CLINGY_SUPERVISOR_PID=$$ "$@" </dev/null &
child_pid=$!

# A terminal supervisor may be blocked in read when its direct child exits.
# Wake it; the loop distinguishes this from EOF by checking child liveness.
trap 'exec 0<&-' CHLD

# A terminal read also prevents the main loop from polling its original
# parent. This headless monitor converts parent loss into the same HUP path
# used by a terminal hangup; cleanup terminates and reaps the monitor itself.
if [ "$owner_pid" -gt 1 ]; then
  (
    while kill -0 "$owner_pid" 2>/dev/null; do sleep 0.1; done
    kill -HUP "$$" 2>/dev/null || true
  ) </dev/null &
  parent_monitor_pid=$!
fi

while [ -z "$requested_exit" ]; do
  if ! kill -0 "$child_pid" 2>/dev/null; then
    wait "$child_pid" 2>/dev/null
    requested_exit=$?
    break
  fi
  if [ "$owner_pid" -gt 1 ] && ! kill -0 "$owner_pid" 2>/dev/null; then
    requested_exit=129
    break
  fi
  if [ "$watch_stdin" -eq 1 ] && [ -t 0 ]; then
    IFS= read -r ignored
    read_status=$?
    # This read has no timeout: status 1 is therefore a real terminal EOF.
    # Signals and child exit interrupt it. Confirm the child is still alive so
    # a CHLD interruption cannot be mistaken for Ctrl-D.
    if [ "$read_status" -eq 1 ] && kill -0 "$child_pid" 2>/dev/null && [ -z "$requested_exit" ]; then requested_exit=0; fi
  else
    sleep 0.1
  fi
done

printf '%s\n' "$label: stopping..." >&2
cleanup
trap - EXIT
printf '%s\n' "$label: stopped." >&2
exit "${requested_exit:-0}"
]=]
end

return M
