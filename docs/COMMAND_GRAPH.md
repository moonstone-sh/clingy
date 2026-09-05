# Clingy Command Graph Specification (`clingy.command-graph.v0`)

## 1. Abstract & Scope

This document specifies the normative structure, semantics, and contracts of the **Clingy Command Graph Intermediate Representation (IR)** version `clingy.command-graph.v0`.

The Command Graph is a flat, content-addressed, serializable semantic description of a CLI application's command topology, declarations, cardinality algebra, visibility rules, parser policies, and lifecycle hooks. It is produced by normalizing the declarative Declaration AST (`c.create`) and is the single source of truth for:
1. Compile-time validation and conflict rejection.
2. Fast runtime router compilation (`CompiledRouter`).
3. External tools, reflection inspectors (`c.reflect(app)`), shell completion generators, manpage exporters, and OpenAPI/CLI schema projection.

---

## 2. Invariants & Guarantees

1. **Format Tag**: Every graph must declare `format = "clingy.command-graph.v0"`.
2. **Deterministic Graph Topology**: The graph is represented as flat dictionaries (`nodes`, `bindings`) indexed by stable unique string IDs.
3. **Single Declaration Ownership**: Every binding belongs to exactly one `owner` node ID.
4. **Explicit Visibility**: Visibility outside the owner node is strictly `"local"` (the owner node only) or `"descendants"` (explicitly declared via `c.inherit(...)`).
5. **No Ad-Hoc Runtime Mutation**: The Command Graph IR is immutable after normalization. Compiled routers derive runtime lookup indexes from the graph without mutating the graph structure.
6. **Zero Closure Leaks**: Bindings do not contain runtime closures. Handlers, lifecycle hooks, and signal policies are attached to node definitions.

---

## 3. Top-Level Graph Schema

```lua
---@class ClingyCommandGraph
---@field format string @ Always "clingy.command-graph.v0"
---@field name string @ Root binary or application name
---@field version string @ Application semantic version string
---@field description string? @ Application description
---@field root string @ Node ID of the root command ("root")
---@field nodes table<string, ClingyNodeIR> @ Map of node ID to Node IR
---@field bindings table<string, ClingyBindingIR> @ Map of binding ID to Binding IR
```

---

## 4. Node IR Schema (`ClingyNodeIR`)

Each command node in the command topology is represented as a `ClingyNodeIR` object:

```lua
---@class ClingyNodeIR
---@field id string @ Unique dotted path ID (e.g. "root", "root.init", "root.init.instant")
---@field name string @ Command segment name (e.g. "mycli", "init", "instant")
---@field parent string? @ Parent node ID (nil for root)
---@field aliases string[] @ Array of alternative invocation names
---@field children table<string, string> @ Lookup map: token (name or alias) -> primary child name
---@field child_order string[] @ Deterministically sorted array of primary child names
---@field bindings string[] @ Ordered list of binding IDs owned directly by this node
---@field declaration_order string[] @ Ordered list of binding IDs in source declaration order
---@field parser_policy ClingyParserPolicy @ Parser configuration for this segment
---@field handler function? @ Execution callback: fn(ctx: ClingyContext) -> any
---@field signals ClingySignalsPolicy? @ Signal dispatch callbacks
---@field stages ClingyStageDeclaration[] @ Custom lifecycle stages defined on this node
---@field passthrough_key string? @ Result key if c.passthrough(key) was declared
---@field metadata table @ Arbitrary user metadata table
```

### Parser Policy (`ClingyParserPolicy`)

```lua
---@class ClingyParserPolicy
---@field ordering "interspersed"|"leading"|"ordered" @ Segment token ordering rule
---@field ordering_inherited boolean @ Whether ordering policy cascades to child segments
---@field short_clusters boolean @ Whether short flag clusters (e.g. -xvf) are enabled
---@field short_clusters_inherited boolean @ Whether short cluster capability cascades
```

---

## 5. Binding IR Schema (`ClingyBindingIR`)

Arguments, options, flags, and passthrough declarations are normalized into uniform `ClingyBindingIR` objects:

```lua
---@class ClingyBindingIR
---@field id string @ Unique ID: "{owner_id}:{result_key}" (e.g. "root:verbose", "root.build:define")
---@field owner string @ Node ID of the declaring owner node
---@field kind "arg"|"option"|"flag"|"passthrough" @ Structural binding kind
---@field name string @ Primary display name (e.g. "profile", "--config", "-v")
---@field names string[]? @ All registered CLI tokens (short and long aliases)
---@field result_key string @ Output table key in `ctx.args`
---@field visibility "local"|"descendants" @ Visibility scope across command segments
---@field position integer? @ 1-based positional argument order (nil for options/flags)
---@field schema table? @ Valua schema specification / Standard Schema v1 object
---@field occurrence ClingyOccurrenceRange @ Occurrence bounds (times token may appear)
---@field values ClingyValueRange @ Value consumption bounds per occurrence
---@field aggregate "scalar"|"array" @ Storage strategy in `ctx.args`
---@field default any @ Clingy-level fallback default value if omitted
---@field declaration_index integer @ Source declaration index within the owner node
```

### Cardinality Algebra (`occurrence` and `values`)

```lua
---@class ClingyOccurrenceRange
---@field min integer @ Minimum times declaration must appear (0 = optional, 1 = required)
---@field max integer? @ Maximum times declaration may appear (nil = unbounded/repeated)

---@class ClingyValueRange
---@field min integer @ Minimum values consumed per occurrence (0 for flags, 1 for options)
---@field max integer? @ Maximum values consumed per occurrence (nil for variadic passthrough)
```

| Declaration Shape | `kind` | `occurrence` | `values` | `aggregate` |
|---|---|---|---|---|
| `c.flag("-v", "--verbose")` | `"flag"` | `{ min = 0, max = 1 }` | `{ min = 0, max = 0 }` | `"scalar"` |
| `c.option("-c", "--config", v.string())` | `"option"` | `{ min = 0, max = 1 }` | `{ min = 1, max = 1 }` | `"scalar"` |
| `c.required(c.option("-e", v.string()))` | `"option"` | `{ min = 1, max = 1 }` | `{ min = 1, max = 1 }` | `"scalar"` |
| `c.repeated(c.option("-D", v.string()))` | `"option"` | `{ min = 0, max = nil }` | `{ min = 1, max = 1 }` | `"array"` |
| `c.arg("target", v.string())` | `"arg"` | `{ min = 1, max = 1 }` | `{ min = 1, max = 1 }` | `"scalar"` |
| `c.optional(c.arg("out", v.string()))` | `"arg"` | `{ min = 0, max = 1 }` | `{ min = 1, max = 1 }` | `"scalar"` |
| `c.repeated(c.arg("files", v.string()))` | `"arg"` | `{ min = 1, max = nil }` | `{ min = 1, max = 1 }` | `"array"` |
| `c.passthrough("args")` | `"passthrough"` | `{ min = 0, max = 1 }` | `{ min = 0, max = nil }` | `"array"` |

---

## 6. Two-Stage Compilation Pipeline

The Clingy engine strictly separates AST normalization from runtime index compilation:

```text
  c.create({ ... }) [Declaration AST]
          │
          ▼  M.normalize(config)
  ClingyCommandGraph (clingy.command-graph.v0)
          │
          ▼  M.validate_graph(graph)  [Conflict & Ambiguity Detection]
  Verified Command Graph
          │
          ▼  M.compile_router(graph)
  CompiledRouter [Fast Runtime Lookup Maps & Effective Policies]
```

### Fast Runtime Indexes in `CompiledRouter`
The `CompiledRouter` constructs precomputed lookup structures per executable node:
- `node.visible_options_by_name`: Direct lookup map `token -> binding_ir` resolving local and inherited flags/options.
- `node.child_names_map`: Lookup map for child commands and child aliases.
- `node.args`: Array of positional argument bindings in evaluation order.
- `node.mode`: Effective grammar ordering mode (`"interspersed"`, `"leading"`, or `"ordered"`).
- `node.short_clusters`: Precomputed boolean flag indicating whether short clustering is active on the node.
