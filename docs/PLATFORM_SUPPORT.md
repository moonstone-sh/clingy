# Clingy Platform & Runtime Support (`docs/PLATFORM_SUPPORT.md`)

## 1. Supported Operating Systems

| Platform | Core Argv Parsing | Terminal UI (Fancy / Plain) | Signals (INT / TERM) | Process Supervision | Control IPC |
|---|---|---|---|---|---|
| **macOS (Darwin)** | Full Support | Full Support (VT100 / UTF-8) | Full Support (POSIX) | Full Support | Full Support |
| **Linux** | Full Support | Full Support (VT100 / UTF-8) | Full Support (POSIX) | Full Support | Full Support |
| **Windows** | Full Support | Full Support (Windows Terminal / conhost) | Supported (`SIGINT` Ctrl+C) | Supported (`os.execute` / `io.popen`) | Supported (In-Memory Queue) |

---

## 2. Supported Lua Runtimes

| Runtime | Version Target | Status | Notes |
|---|---|---|---|
| **PUC Lua** | `5.4.x` | **Tier 1 (Primary)** | Native integers (`math.tointeger`), full Standard Schema v1 support |
| **LuaJIT** | `2.1.x` | **Tier 1 (Primary)** | Native JIT compilation, fast token parsing |
| **PUC Lua** | `5.1.x` / `5.2.x` / `5.3.x` | **Tier 2 (Compatible)** | Standard Lua compatibility layer |

### Lua flavors

Clingy ships one source tree for every runtime above and no Moonstone flavor
variants (`mod@lua54.lua` files). The version differences it depends on live in
`src/clingy/compat.lua`:

- `compat.to_integer`: `math.tointeger` on 5.3+, an equivalent integral-value
  check on 5.1, 5.2 and LuaJIT, so integer schemas classify the same way
  everywhere.
- `compat.exit_status`: turns what `os.execute` and a popen handle's `close()`
  return into a shell-style exit code. Lua 5.2+ returns
  `true|nil, "exit"|"signal", code`; Lua 5.1 and LuaJIT return a raw `system()`
  status (768 for `exit 3` on POSIX).

A variant would not remove the runtime check here: LuaJIT returns the 5.1
shape by default and the 5.2 shape when built with
`LUAJIT_ENABLE_LUA52COMPAT`, and the `luajit` flavor cannot tell them apart.

Known limit: on Lua 5.1 and LuaJIT, a popen handle's `close()` does not report
the child's status, so `capture` and `protocol` processes report exit code 0
there even when the command failed. `inherit` and `interactive` processes report
the real code on every runtime.

---

## 3. Platform Detection & Presentation Fallbacks

1. **TTY Detection**:
   - Inspects `TERM` environment variable and `CI` environment variable.
   - If `TERM == "dumb"` or `CI == "true"`, auto mode resolves to `plain`.
2. **ANSI Support**:
   - Emits zero ANSI codes in `plain`, `quiet`, and `json` modes.
   - Preserves UTF-8 output across all modern terminals.
