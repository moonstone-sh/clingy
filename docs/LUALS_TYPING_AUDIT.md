# Clingy v0 — LuaLS Typing & Semantic Duality Audit

## 1. Overview & Type System Authority

Clingy's type system is designed around a strict architectural invariant:

> **LuaLS adapts to Clingy; Clingy does not distort its runtime DSL for LuaLS.**

The authoritative chain of truth flows downstream:

```text
Valua (Value Semantics & Reflection)
    ↓
Clingy Declaration DSL (Lexical CLI Grammar)
    ↓
Command Graph IR (Normalized Semantic Truth)
    ↓
Compiled Router (Runtime Execution)
    ↓
LuaLS LuaCATS / Plugin (Static Projection & IDE Experience)
```

Typing exists to reflect runtime semantics accurately without imposing boilerplate onto application code.

---

## 2. LuaCATS Class Model & Generic Annotations

Clingy provides first-class LuaCATS definitions located in `luals/library/clingy.lua`:

### `clingy.Binding<O>`
Represents a typed declaration handle returned by DSL constructors. The generic parameter `O` models the **output value** delivered to runtime handlers.

```lua
---@class clingy.Binding<O>
---@field _tag "declaration"
---@field kind "arg"|"option"|"flag"|"passthrough"
---@field name? string
---@field names? string[]
---@field result_key string
---@field schema? any
---@field occurrence { min: integer?, max: integer? }
---@field values { min: integer, max: integer? }
---@field aggregate "scalar"|"array"
---@field default? any
```

### `clingy.Context<A>`
Represents the runtime execution context passed to `c.run(function(ctx) ... end)`. The generic parameter `A` models the typed record of parsed arguments.

```lua
---@generic A : table
---@class clingy.Context<A>
---@field args A
---@field route { node: string, node_ir?: table, args: table<string, any> }[]
---@field passthrough string[]
---@field target_node table
---@field bus any
---@field composer any
---@field app clingy.App
```

### Generic `Context:get(binding)`
Resolves argument values by declaration table reference identity:

```lua
---@generic O
---@param binding clingy.Binding<O>|string
---@return O?
function Context:get(binding)
end
```

---

## 3. Valua Type Duality Audit

A fundamental distinction exists between **lexical parsing input** and **handler output**:

```text
                  argv lexical string ("8080")
                             │
                             ▼
                 Valua Input Domain (string)
                             │
                v.transform(tonumber) pipeline
                             │
                             ▼
                 Valua Output Type (number)
                             │
             ┌───────────────┴───────────────┐
             ▼                               ▼
       ctx.args.port                   ctx:get(port)
        (= 8080)                         (= 8080)
```

### Duality Matrix

| Schema Declaration | Lexical Input Domain | Valua Input Type | Valua Output Type `O` | `ctx.args` / `ctx:get()` Type |
| :--- | :--- | :--- | :--- | :--- |
| `c.arg("path")` (no schema) | String token | `string` | `string` | `string` |
| `c.arg("count", v.integer())` | Integer string | `string` | `integer` | `integer` |
| `c.option("-p", "--port", Port)` | Port string | `string` | `number` | `number\|nil` |
| `c.flag("-v", "--verbose")` | Flag presence | `nil` | `boolean` | `boolean` (false when absent) |
| `c.repeated(c.option("-H", Header))` | Repeated strings | `string` | `Header` | `Header[]\|nil` |
| `c.required(c.option("-t", Token))` | Token string | `string` | `Token` | `Token` (guaranteed present) |

### Non-Coercion of Descriptive Metadata
As formalized in Invariant 6, `v.default(schema, val)` is strictly **descriptive metadata** for documentation/reflection. Clingy's runtime parser does not silently inject `schema.metadata.default` into `ctx.args`. Handler typing strictly reflects actual CLI occurrence.

---

## 4. Declaration Runtime Identity vs Normalization

1. **Instantiation**: `c.arg()`, `c.option()`, `c.flag()` return distinct Lua tables tagged with `_tag = "declaration"`.
2. **Cardinality Wrappers**: `c.optional()`, `c.required()`, `c.repeated()` create a wrapped declaration record retaining `_inner = decl`.
3. **Normalization**: The compiler indexes all declaration table references (and inner wrapped references) into `node_ir.decl_map[decl] = binding` and `compiled_node.decl_map[decl] = binding`.
4. **Resolution**: `ctx:get(binding)` checks `target_node.decl_map[binding]` and walks active route segments up to root. Resolution uses exact table pointer equality (`rawequal`).

---

## 5. Audit Conclusions

- **Type Safety**: Full generic output type propagation is achieved without forcing users to extract local variables.
- **Zero Overhead**: LuaCATS annotations in `luals/library/` provide zero-runtime-cost editor typing.
- **Duality Preserved**: Lexical adaptation respects Valua standard schemas while handlers receive fully coerced and validated output types.
