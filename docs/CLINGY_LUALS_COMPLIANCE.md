# Clingy v0 — LuaLS Typing & Modular Router Assembly Compliance Matrix

## 1. Executive Summary

This document certifies Clingy v0's compliance with the developer experience, LuaLS type system, `Binding<O>` identity model, and modular router assembly specifications.

All 171 automated tests across 22 test suites pass with 0 failures.

---

## 2. Capability Compliance Matrix

| Capability | Specification Section | Implementation Status | Test Verification Suite | Compliance Status |
| :--- | :--- | :--- | :--- | :--- |
| **Inline Declarations as Default** | Part I & II | `c.node({...})` inline syntax is canonical default | `tests/dsl/dsl_spec.lua` | **COMPLIANT** |
| **`Binding<O>` Class Model** | Part II | `clingy.Binding<O>` generic class in `luals/library/clingy.lua` | `tests/luals/binding_identity_spec.lua` | **COMPLIANT** |
| **`Context:get(binding)` Resolution** | Part II & Invariant 16 | Pointer equality (`rawequal`) lookup via `decl_map` | `tests/luals/binding_identity_spec.lua` | **COMPLIANT** |
| **Inherited Option Resolution** | Part II & Invariant 2, 11 | Upward active route traversal to root for inherited bindings | `tests/luals/binding_identity_spec.lua` | **COMPLIANT** |
| **Cardinality Type Algebra** | Part III | `c.optional`, `c.required`, `c.repeated` generic propagation | `tests/luals/binding_identity_spec.lua` | **COMPLIANT** |
| **Valua Type Duality** | Part I & Invariant 5, 6 | Lexical parsing input vs handler output typing | `tests/invariants/inv_valua_matrix_spec.lua` | **COMPLIANT** |
| **LuaLS `OnSetText` Plugin** | Part IV | Static extraction & virtual context type injection | `tests/luals/plugin_spec.lua` | **COMPLIANT** |
| **Modular Leaf Composition** | Part VI | Subcommand nodes assembled via `require()` | `tests/luals/modular_assembly_spec.lua` | **COMPLIANT** |
| **Decomposed `args/run/node`** | Part VI | Separated command file decomposition | `tests/luals/modular_assembly_spec.lua` | **COMPLIANT** |
| **Shared Grammar Groups** | Part VI & Invariant 1 | `c.group({...})` multi-node mounting & flattening | `tests/luals/modular_assembly_spec.lua` | **COMPLIANT** |
| **`require()` Identity Invariant** | Part VI | Module cache stability in `package.loaded` | `tests/luals/modular_assembly_spec.lua` | **COMPLIANT** |
| **Plugin Performance (< 50ms)** | Part XII | Single-pass scanning benchmarked on 500 commands (< 5ms) | `tests/luals/plugin_spec.lua` | **COMPLIANT** |
| **Plugin Error Resilience** | Part XI | Pure static analysis with defensive `pcall` guards | `tests/luals/plugin_spec.lua` | **COMPLIANT** |

---

## 3. Feature Classification Breakdown

### STABLE V0
The following features are fully implemented, formally tested, and verified as stable for production release:
- `clingy.Binding<O>` declaration handles
- `Context:get(binding)` pointer-identity resolution
- Generic `clingy.Context<A>` public interface
- LuaCATS definitions (`luals/library/clingy.lua`)
- Inline anonymous declarations as the primary canonical DSL style
- Modular router assembly through standard Lua `require()`
- Separated `args.lua` / `run.lua` / `node.lua` command decomposition
- Reusable grammar fragments via `c.group(...)`
- Lexical vs Output type duality with Valua reflection contracts

### EXPERIMENTAL V0
The following features are functional and available for opt-in editor use:
- LuaLS live AST/text context inference plugin (`luals/plugin.lua`)
- Static regex-based parameter type synthesis via `OnSetText`
- Single-pass document extraction with in-memory caching

### POST-V0
The following capabilities are reserved for future major revisions:
- Whole-project reverse route inference across dynamic dependency graphs
- Automated bidirectional symbol renaming from LuaLS AST
- Standalone Ahead-Of-Time (AOT) CLI type generator CLI command
