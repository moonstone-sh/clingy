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

---

## 3. Platform Detection & Presentation Fallbacks

1. **TTY Detection**:
   - Inspects `TERM` environment variable and `CI` environment variable.
   - If `TERM == "dumb"` or `CI == "true"`, auto mode resolves to `plain`.
2. **ANSI Support**:
   - Emits zero ANSI codes in `plain`, `quiet`, and `json` modes.
   - Preserves UTF-8 output across all modern terminals.
