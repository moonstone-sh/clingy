# Clingy & Standard Schema V1 Typing Decoupling Report

**Status:** PASS  
**Target Codebase:** `/Users/extrordinaire/Workbench/user/clingy`  
**Protocol Boundary:** Standard Schema V1 (`standard_schema.Schema<I, O>`)  
**Test Matrix:** 180 Passed, 0 Failed across 29 test suites  

---

## 1. Residual Architectural Smells Addressed

Following the initial decoupling pass, two critical architectural areas were identified and systematically resolved:

1. **Eliminated Constructor-Name Heuristics in LuaLS Plugin:**
   - The plugin previously attempted to guess types from syntax patterns like `anything.integer()`, `.number()`, `.picklist({...})`.
   - This was not protocol-driven and risked misclassifying arbitrary methods or third-party constructors.
   - **Resolution:** Constructor-name heuristics were completely excised. The plugin now operates strictly via static type resolution (`---@type standard_schema.Schema<I, O>`, `---@return standard_schema.Schema<I, O>`, and variable assignment tracing). Unproven expressions strictly resolve to `unknown`. Bare declarations without schemas (`c.arg("name")`, `c.option("-f")`) evaluate to `string`.

2. **Formalized Runtime Lexical Adaptation Architecture (`c.schema_adapter`):**
   - The engine previously fell back to ad-hoc duck typing on `.kind`, `.type`, `.expects`, or `std.kind`. Standard Schema v1 guarantees only `~standard` with `version`, `vendor`, and `validate`.
   - **Resolution:** Replaced all duck typing with an explicit **Schema Adapter Protocol** (`c.schema_adapter`). Clingy registers a built-in adapter for Valua matching `std.vendor == "valua"`. Third-party schemas can register explicit adapters for string-to-primitive coercion. If no adapter matches, Clingy executes pure Standard Schema protocol behavior: the raw string token from argv is delivered directly into `~standard.validate(token)`.

3. **Strict Static LuaCATS Contract:**
   - Removed loose `schema: any` fallback overloads. `c.arg` and `c.option` require `standard_schema.Schema<I, O>` or bare string arguments.
   - Namespaced Standard Schema definitions under `standard_schema.*` in [`luals/library/clingy.lua`](file:///Users/extrordinaire/Workbench/user/clingy/luals/library/clingy.lua).

---

## 2. Standard Schema Type Contract

Clingy defines the canonical Standard Schema V1 interface in [`luals/library/clingy.lua`](file:///Users/extrordinaire/Workbench/user/clingy/luals/library/clingy.lua):

```lua
---@class standard_schema.Props<I, O>
---@field version 1
---@field vendor string
---@field validate fun(value: any, options?: table): { value?: O, issues?: table[] }
---@field types? { input: I, output: O }

---@class standard_schema.Schema<I, O>
---@field ["~standard"] standard_schema.Props<I, O>

---@alias StandardSchema<I, O> standard_schema.Schema<I, O>
---@alias clingy.StandardSchema<I, O> standard_schema.Schema<I, O>
```

---

## 3. Clingy Constructor Typing & Overloads

```lua
---Declares a positional argument.
---@generic I, O
---@param name string
---@param schema standard_schema.Schema<I, O>
---@return clingy.Binding<O>
---@overload fun(name: string): clingy.Binding<string>
function c.arg(name, schema) end

---Declares a named option with a value.
---@generic I, O
---@overload fun(name: string, schema: standard_schema.Schema<I, O>): clingy.Binding<O|nil>
---@overload fun(short: string, long: string, schema: standard_schema.Schema<I, O>): clingy.Binding<O|nil>
---@overload fun(name: string): clingy.Binding<string|nil>
---@overload fun(short: string, long: string): clingy.Binding<string|nil>
---@param ... any Names starting with '-' followed by optional schema
---@return clingy.Binding<any>
function c.option(...) end
```

---

## 4. Schema Adapter Protocol (`c.schema_adapter`)

For schema engines requiring lexical string-to-primitive coercion (e.g. converting `"1024"` to `1024` before running integer validation), Clingy exposes:

```lua
---@class clingy.SchemaAdapter
---@field vendor string
---@field match fun(schema: any): boolean
---@field inspect? fun(schema: any): { kind?: string, description?: string, default?: any, options?: string[] }
---@field coerce? fun(schema: any, token: string): any

---Registers a custom schema adapter.
---@param adapter clingy.SchemaAdapter
function c.schema_adapter(adapter) end
```

### Protocol Flow:
1. `c.create()` inspects schemas using registered adapters (e.g., extracting descriptions/defaults for help text).
2. During argv parsing, if `adapter = find_adapter(schema)` exists and defines `coerce`, `adapter.coerce(schema, token)` is invoked.
3. If no adapter matches, the raw string token from argv is passed untouched.
4. Validation is executed via `~standard.validate(value)` or direct validator function.

---

## 5. LuaLS Plugin Proof-Driven Engine

[`luals/plugin.lua`](file:///Users/extrordinaire/Workbench/user/clingy/luals/plugin.lua) extracts context types through verified source metadata:

1. **Explicit Type Annotations:** `---@type standard_schema.Schema<any, number>` &rarr; `number`.
2. **Function Return Annotations:** `---@return standard_schema.Schema<any, string>` &rarr; `string`.
3. **Variable Assignment Chains:** Follows `local A = B` to resolve underlying annotated schema.
4. **Bare Declarations:** `c.arg("path")` &rarr; `string`.
5. **Unproven Schemas:** `c.arg("target", foreign.custom())` without annotations strictly resolves to `unknown`. Zero heuristic guessing on constructor names.

---

## 6. Verification & Test Matrix

- **Total Tests:** 180
- **Passed:** 180
- **Failed:** 0
- **Test Suites Executed:** 29 suites covering all 24 Invariants, parser property tests, LuaLS plugin benchmarks (<50ms for 500 commands), custom schema adapters, mixed validator routers, and complete Valua absence simulation.

---

## 7. Ship Recommendation

**PASS** — Decoupling, typing boundaries, and adapter protocols are fully verified and hardened.
