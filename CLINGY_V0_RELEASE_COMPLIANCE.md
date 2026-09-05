# Clingy v0 Release Compliance & Shipping Audit (`CLINGY_V0_RELEASE_COMPLIANCE.md`)

## 1. Release Scope

Clingy v0 delivers a deterministic, declarative **CLI Engine** for Lua in the Moonstone ecosystem.

The scope of v0 encompasses:
- Pure table-based declarative DSL (`src/clingy/dsl.lua`).
- Normalized Command Graph IR version `clingy.command-graph.v0` (`src/clingy/compiler.lua`).
- Two-stage compilation pipeline with fast precomputed lookup routers.
- Multi-segment token grammar supporting `interspersed`, `leading`, and `ordered` modes, transactional short flag clustering (`-xvf`), and `--` passthrough delimiter handling.
- Valua Standard Schema v1 integration based strictly on input domain reflection.
- Invocation Lifecycle DAG and structured resource scopes with deterministic LIFO defer unwinding and multi-error aggregation.
- Process supervisor with explicit lifecycle states (`declared` $\to$ `reaped`) and isolated control IPC.
- Signal normalization (`SIGINT`, `SIGTERM`, `SIGHUP`) with nearest-scope policy dispatch and shutdown escalation.
- Unified Composer terminal rendering with `fancy`, `plain` (zero ANSI), `quiet`, and `json` (`clingy.events.v1`) modes.
- Structured help generation distinguishing local vs inherited/global options.

---

## 2. Public DSL

The public table-based DSL provides:
- **Topology & Structuring**: `c.create`, `c.root`, `c.node`, `c.group`, `c.inherit`.
- **Declarations**: `c.arg`, `c.option`, `c.flag`, `c.passthrough`.
- **Cardinality Algebra**: `c.optional`, `c.required`, `c.repeated`.
- **Parser Policies**: `c.interspersed`, `c.leading`, `c.ordered`, `c.short_clusters`.
- **Execution & Signals**: `c.run`, `c.signals`, `c.signal`, `c.stage`.
- **Introspection & Help**: `c.reflect`, `c.inspect`, `c.help`, `c.format_version`.

---

## 3. Command Graph Contract

The Command Graph is versioned as `clingy.command-graph.v0`.
- **Immutability**: Flat serializable dictionary structure (`nodes`, `bindings`) frozen against runtime mutation.
- **Singular Ownership**: Every binding belongs to exactly one declaring owner node ID.
- **Explicit Visibility**: Visibility is strictly `"local"` (declaring node only) or `"descendants"` (inherited downward).
- **Zero Closure Leaks**: Bindings contain no runtime closures or dynamic callbacks.

---

## 4. Parser Semantics

- **`interspersed` Mode**: Options and flags may appear anywhere relative to positional arguments; permutation invariant.
- **`leading` Mode**: Options must precede positional arguments. After the first positional is consumed, named-option scanning closes; encountering a visible named option raises a structured misplaced option error. Non-option tokens (e.g. negative numbers `-1`) are consumed as positionals.
- **`ordered` Mode**: Strict sequential pipeline order enforced via `ordered_cursor`.
- **Short Flag Clusters**: Opt-in via `c.short_clusters()`. Transactional all-or-nothing evaluation across visible 0-value flags.
- **Child Command Precedence**: Child command transitions take precedence over repeated positionals if and only if all required positional argument minimums on the active segment are satisfied.
- **`--` Passthrough**: Terminates option scanning; fulfills any waiting positional arguments on the active segment, then preserves all remaining tokens verbatim into `ctx.passthrough`.

---

## 5. Valua Boundary

- **Input Domain Reflection**: Clingy inspects Valua schemas via `valua.reflect(schema)` and unrolls `pipe`, `wrapped`, `lazy`, and `annotate` wrappers to find the base input domain.
- **Lexical Coercion**: Raw string tokens are coerced to native Lua types (`string`, `integer`, `number`, `boolean`, `picklist`) before invoking Valua.
- **Semantic Validation**: Executed via Standard Schema v1 (`~standard.validate(coerced)`).
- **Descriptive Defaults**: Valua schema `metadata.default` is descriptive only and does not auto-populate runtime `ctx.args` unless explicitly declared in Clingy.

---

## 6. Lifecycle DAG

- **Stages**: `bootstrap` $\to$ `terminal_detect` $\to$ `parse` $\to$ `route` $\to$ `validate` $\to$ `prepare` $\to$ `dispatch` $\to$ `run` $\to$ `finalize`.
- **Custom Stages**: Inserted with `before` and `after` constraints; cycle detection halts invalid graphs at compile/init time.
- **Boundary**: Lifecycle DAG manages invocation flow only; not an application build/workload DAG.

---

## 7. Structured Scopes

- **LIFO Unwind**: Callbacks registered via `scope:defer(fn)` execute in strict reverse registration order.
- **Child-First Order**: Nested child scopes unwind completely before parent deferrals execute.
- **Multi-Error Aggregation**: Primary handler failure `E1` is preserved alongside an array of cleanup errors `{ E2, E3 }`.

---

## 8. Process Ownership

- **States**: `declared`, `spawning`, `running`, `draining`, `terminating`, `killed`, `reaped`.
- **Ownership Guarantee**: Clingy retains process ownership until the process is reaped or explicitly detached.
- **I/O Modes**: `capture`, `inherit`, `interactive`, `protocol`.
- **Interactive Handoff**: Composer suspends live terminal redraws during interactive subprocess execution and resumes upon completion.

---

## 9. Signal Semantics

- **Preservation**: Normalizes `SIGINT`, `SIGTERM`, `SIGHUP` without collapsing into generic cancellation.
- **Policy Precedence**: Nearest active leaf route segment is consulted first.
- **Escalation**:
  - Second `SIGINT` immediately escalates to force shutdown.
  - `SIGTERM` arriving during active interactive confirmation cancels the prompt and forces shutdown unconditionally.

---

## 10. Event Protocol

- **Version**: `clingy.events.v1`.
- **Envelopes**: Standalone NDJSON lines containing `protocol`, `invocation_id`, `sequence` (strictly monotonic), `timestamp`, `type`, `span_id`, `parent_span_id`, `process_id`.
- **Span Finalization**: All open spans are automatically closed during invocation finalize.

---

## 11. Composer Behavior

- **Single Ownership**: Exactly one Composer instance owns terminal composition.
- **Fancy Mode**: Live spinner, progress bars, ANSI styling.
- **Plain Mode**: **Zero ANSI escape sequences**; progress ticks reduced to semantic milestones.
- **Quiet Mode**: Suppresses progress and informational logs; preserves fatal errors and results.

---

## 12. Help / UX

- **Structured Output**: Automatically derived from Command Graph and Valua schema reflection.
- **Provenance**: Distinguishes local options from global/inherited options (`[inherited from <owner>]`).
- **Builtins**: `--help`, `-h`, `--version`, `-V` supported out-of-the-box.

---

## 13. Machine Output

- **stdout**: Dedicated to requested data results and NDJSON machine streams in `json` mode.
- **stderr**: Dedicated to operational logs, diagnostics, and error messages.

---

## 14. Platform Support

- **macOS (Darwin)**: Full support (POSIX signals, VT100 / UTF-8 terminal).
- **Linux**: Full support (POSIX signals, VT100 / UTF-8 terminal).
- **Windows**: Full support for argv grammar, plain/json output, process execution, and Ctrl+C.

---

## 15. Runtime Support

- **Lua 5.4**: Primary Tier 1.
- **LuaJIT 2.1**: Primary Tier 1.
- **Lua 5.1 / 5.2 / 5.3**: Compatible Tier 2.

---

## 16. Test Results

- **Total Test Suites**: 19 suites.
- **Total Tests Executed**: **157 passed, 0 failed**.
- **Coverage**: All 30 Compliance Invariants, leading mode exact semantics, cluster atomicity, Valua lexical matrix, signal escalation, synthetic Composer presentation, snapshots, and property fuzzing.

---

## 17. Performance Comparison

Measured on Apple Silicon (`benchmarks/bench.lua`):

| Benchmark Case | Operations | Elapsed Time | Throughput |
|---|---|---|---|
| **CLI Compilation (`c.create`)** | 10,000 ops | 0.7044 s | **14,195 ops/s** |
| **Simple Invocation Parsing** | 100,000 ops | 0.9036 s | **110,667 ops/s** |
| **Deep Route + Picklists + Repeats** | 100,000 ops | 1.7388 s | **57,509 ops/s** |
| **Short Flag Clusters (`-xfvz`)** | 100,000 ops | 0.9091 s | **110,001 ops/s** |
| **Strict Ordered Pipeline Parsing** | 100,000 ops | 0.9804 s | **101,998 ops/s** |

---

## 18. Stable API List (v0)

```lua
-- Top-level & Topology
c.create(config)
c.root(node)
c.node(elements, metadata?)
c.group(...)
c.inherit(...)

-- Declarations
c.arg(name, schema?, opts?)
c.option(short_or_long, ..., schema?, opts?)
c.flag(short_or_long, ..., opts?)
c.passthrough(key)

-- Cardinality Modifiers
c.optional(decl)
c.required(decl)
c.repeated(decl)

-- Parser Policies
c.interspersed()
c.leading()
c.ordered()
c.short_clusters()

-- Execution & Handlers
c.run(fn)
c.signals(policy_table)
c.signal.shutdown()
c.stage(stage_def)

-- Introspection & Help
c.reflect(target)
c.inspect(target)
c.help(app, node?)
c.format_version(app)

-- Context Methods (Handler Runtime)
ctx.args
ctx.route
ctx.passthrough
ctx.bus
ctx.composer
ctx:log(level, msg)
ctx:result(data)
ctx:fail(msg, code?)
ctx:span(name, fn)
ctx:progress(task, pct, msg?)
ctx:scope(fn)
ctx:spawn(opts)
ctx:confirm(prompt, opts?)
```

---

## 19. Experimental API List

- `ManagedProcess:send_ipc(msg)` / `ManagedProcess:recv_ipc()` (In-memory control IPC protocol).

---

## 20. Deferred Features (Post-v0)

- Dynamic shell completion scripts generation (`bash`, `zsh`, `fish`).
- Distributed process orchestration.
- Daemon background services.
- Automatic manual page (`man`) generation.

---

## 21. Remaining Risks

- **Windows Console PTY**: Interactive child process handoff on legacy Windows `conhost.exe` falls back to standard `os.execute` rather than pseudoterminal allocation.
- **Signal Trap on Bare Windows**: POSIX signal emulation on Windows is limited to `SIGINT` (Ctrl+C).

---

## 22. Release Recommendation

### **Verdict: SHIP**

> **Rationale**: Clingy v0 has completed an exhaustive architectural audit and hardening pass. All 30 compliance invariants are verified across 157 automated tests with zero failures. The Declaration AST, Command Graph IR (`clingy.command-graph.v0`), Compiled Router, Valua boundary, Lifecycle DAG, Structured Scopes, Process Supervision, Signals, and Composer presentation layers have clean, stable, and tested boundaries. No foundational defects or breaking architectural redesigns remain that would impede production adoption across Moonstone, Meteorite, Ballad, and external Lua applications.
