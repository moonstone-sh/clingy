# Foreground process supervision

`require("clingy.process").supervisor_script(opts)` returns a Bash script that
owns a headless command and its process group. A shell launcher should `exec
bash` with that script after Lua has written it. This keeps terminal signals
outside Lua's `os.execute`, which changes SIGINT handling while it waits.

```lua
local script = require("clingy.process").supervisor_script({
  argv = { "lua", "watch.lua" },
  cwd = "/path/to/project",
  env = { APP_MODE = "development" },
  stdin_eof = true,
  grace_ms = 2000,
  label = "My dev server",
  lock_dir = "/path/to/project/.state/session.lock",
  cleanup_files = { "/path/to/project/.state/server.pid" },
})
```

`argv` is required. All other fields are optional. Arguments, paths and
environment values are shell-quoted; environment keys must be identifiers.
The caller creates the parent directories and writes the generated script.
`cleanup_files` names individual files owned by this session, never directories.
An optional atomic directory lock rejects simultaneous owners. A session killed
with SIGKILL may leave its lock; inspect `owner.pid` before removing that stale
lock. Existing locks are never reclaimed using a guessed process identity.

The supervisor gives its child a separate process group, closes the child's
stdin, and keeps stdout and stderr inherited. It handles INT, TERM and HUP with
exit statuses 130, 143 and 129. Terminal EOF exits with status 0 when `stdin_eof`
is enabled. Redirected stdin EOF does not stop the child. The foreground owner
reads terminal EOF through a duplicate descriptor. Child-status wakeups close
and reopen only that duplicate, so they cannot be mistaken for Ctrl-D and never
close or repurpose standard input. The supervisor does not change terminal modes
or forward input to an interactive application.

Normal command completion, command failure, cancellation and original-parent
death all run the same cleanup. The owner sends TERM to the whole child group,
waits up to `grace_ms`, then sends KILL and waits for its direct child. Repeated
signals force KILL. Descendants still in the group are stopped even when their
immediate parent has exited. The child receives `CLINGY_SUPERVISED=1` and the
owner's PID in `CLINGY_SUPERVISOR_PID` for session-scoped coordination.

This backend requires Bash 3.2 or later on macOS or Linux. Descendants must keep
the inherited process group; deliberate daemonization, `setsid`, and nested job
control are outside its contract. The operating system reaps orphan descendants;
the supervisor can wait only for its direct child. SIGKILL of the supervisor
cannot run cleanup. Native Windows job objects are not implemented.

The older `ManagedProcess` API is a synchronous command adapter: `start()`
prepares a command and `wait()` executes it. Its state-only `terminate()` and
`kill()` methods do not signal OS processes. Use the supervisor backend for
long-running session ownership. This addition does not silently change that
existing API's execution timing or interactive presentation behavior.

Run `moon run test-process-supervision` for real process, signal and PTY tests.
