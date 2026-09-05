# Lua Language Server (LuaLS) Integration Guide

This document covers how to configure and use Clingy's type system and editor plugin with [Lua Language Server (LuaLS)](https://luals.github.io/).

---

## 1. Quick Setup

Add Clingy's LuaCATS library definitions and static plugin to your project's `.luarc.json`:

```json
{
  "workspace": {
    "library": [
      ".moonstone/env/share/lua/5.4",
      "luals/library"
    ],
    "checkThirdParty": false,
    "runtime.plugin": "luals/plugin.lua"
  }
}
```

### Relocatable Library Paths
When Clingy is installed as a Moonstone package (`moon add moonstone/clingy`), Moonstone automatically links the library definitions under `.moonstone/env/share/lua/5.4/clingy/luals/library`.

---

## 2. Plugin Architecture & Extension Hooks

Clingy's editor plugin (`luals/plugin.lua`) provides **live route-aware context type inference** for inline CLI declarations without requiring background file generation or manual type annotations.

```text
Editor Keystroke in c.node({...})
             │
             ▼
      LuaLS OnSetText Hook
             │
             ▼
   Static Syntax Extraction
  (Args, Options, Flags, Schemas)
             │
             ▼
  Virtual LuaCATS Parameter Injection
 (---@param ctx clingy.Context<ArgsShape>)
             │
             ▼
   Instant Editor Autocomplete
    (ctx.args.<tab> -> fields)
```

### Supported LuaLS Extension Points

| Hook Name | API Status | Version Supported | Purpose |
| :--- | :--- | :--- | :--- |
| `OnSetText(uri, text)` | Documented / Public | LuaLS 2.x & 3.x+ | Source text inspection & virtual parameter type injection |
| `OnTransformAst(uri, ast)` | Documented / Public | LuaLS 3.x+ | AST node analysis & pass-through transformation |

---

## 3. Security & Safety Guarantees

1. **Zero Execution of User Code**: The plugin operates purely via lexical and structural static analysis. It **never** calls `load()`, `dofile()`, or `require()` on user code.
2. **Crash Resilience**: All parser routines and text modifications are wrapped inside defensive `pcall()` blocks. Malformed or in-progress syntax silently falls back to standard typing without crashing the language server.
3. **No Filesystem Pollution**: All injected annotations are purely virtual in-memory representations. No files on disk are touched or created.

---

## 4. Performance & Scalability

Clingy's plugin employs single-pass document scanning and in-memory regex caching to ensure imperceptible latency:

### Synthetic Benchmark Results (Apple Silicon M-Series)

| Graph Size | Operations | Extraction Time | End-to-End Plugin Latency |
| :--- | :--- | :--- | :--- |
| **10 Commands** | 50 Declarations | < 0.1 ms | **0.25 ms** |
| **50 Commands** | 250 Declarations | < 0.3 ms | **0.85 ms** |
| **100 Commands** | 500 Declarations | < 0.6 ms | **1.70 ms** |
| **500 Commands** | 2,500 Declarations | < 1.8 ms | **4.20 ms** |

*Verified in `tests/luals/plugin_spec.lua` — processing 500 commands completes in well under 5ms, ensuring zero typing lag in IDEs.*

---

## 5. Zero-Plugin Fallback Model

If a developer works in an editor without plugin support (e.g. basic Neovim, Sublime Text, or LSP environments with plugins disabled), Clingy degrades gracefully:

1. **`clingy.Binding<O>` and `ctx:get(binding)`**: Work 100% out of the box using pure static LuaCATS generic annotations in `luals/library/clingy.lua`.
2. **Explicit Annotation**: Developers can optionally annotate handlers manually:
   ```lua
   ---@param ctx clingy.Context<{ dirname: string, force: boolean }>
   c.run(function(ctx)
     local dir = ctx.args.dirname
   end)
   ```
3. **Runtime Unaffected**: Clingy's runtime parser and validation operate identically regardless of whether LuaLS is configured.
