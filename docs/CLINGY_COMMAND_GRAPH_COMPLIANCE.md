# Clingy Command Graph & Engine Compliance Matrix (30 Invariants)

## 1. Matrix Overview

This document provides a normative verification matrix mapping each of Clingy's 30 fundamental and architectural invariants to its representation in the Command Graph IR, compiler validation check, runtime enforcement, and automated test suite.

---

## 2. Invariant Compliance Table

| Invariant | Name & Description | IR Representation (`clingy.command-graph.v0`) | Compiler Validation (`compiler.lua`) | Runtime Enforcement (`parser.lua` / `engine.lua`) | Test Verification |
|---|---|---|---|---|---|
| **INV-01** | Single Declaration Ownership | `binding.owner = node_id` | Enforces 1 owner per binding during normalization | `ctx.route[i].args` assigns tokens strictly to owner segment | `tests/invariants/inv_01_02_owner_inherit_spec.lua` |
| **INV-02** | Downward Explicit Inheritance | `binding.visibility = "descendants"` | Cascades inherited bindings to child subtrees only | Unknown option error raised if sibling/parent accesses uninherited binding | `tests/invariants/inv_01_02_owner_inherit_spec.lua` |
| **INV-03** | Parser Ordering vs Visibility Separation | `node.parser_policy.ordering` separate from `binding.visibility` | Policy and binding declarations orthogonal in AST | Parser enforces ordering without modifying visible bindings table | `tests/invariants/inv_03_07_grammar_modes_spec.lua` |
| **INV-04** | Cardinality Algebra Separation | `binding.occurrence = { min, max }`, `values = { min, max }` | Algebraic normalization via `c.optional/required/repeated` | Enforces min/max counts on occurrence and values | `tests/invariants/inv_04_05_06_valua_cardinality_spec.lua` |
| **INV-05** | Valua Semantic Validation | `binding.schema` stores Standard Schema object | Preserves schema object in IR | Invokes `~standard.validate(coerced)` on all values | `tests/invariants/inv_04_05_06_valua_cardinality_spec.lua` |
| **INV-06** | Clingy Lexical Grammar Ownership | `binding.kind` (`arg`, `option`, `flag`, `passthrough`) | Derives argument/option names and token prefixes | `adapter.adapt_and_validate` coerces argv strings to primitives | `tests/invariants/inv_04_05_06_valua_cardinality_spec.lua` |
| **INV-07** | Distinct Grammar Modes | `node.parser_policy.ordering = "interspersed"\|"leading"\|"ordered"` | Rejects multiple conflicting parser modes on one node | Parser executes distinct branch logic per segment mode | `tests/invariants/inv_03_07_grammar_modes_spec.lua` |
| **INV-08** | Explicit Opt-In Short Clustering | `node.parser_policy.short_clusters = true` | Only set when `c.short_clusters()` is declared | Decomposes `-xvf` only if `short_clusters == true` and all are 0-value flags | `tests/invariants/inv_08_short_clusters_spec.lua` |
| **INV-09** | Routing Transitions Define Segments | `route = { { node = "root", ... }, { node = "sub", ... } }` | Builds hierarchical node tree with unique IDs | Every child transition pushes new segment to `ctx.route` | `tests/invariants/inv_09_10_11_segment_routing_spec.lua` |
| **INV-10** | Local Ancestor Flag Isolation | `binding.visibility = "local"` | Local bindings omitted from descendant `visible_options_by_name` | Parser rejects local ancestor flag after segment transition | `tests/invariants/inv_09_10_11_segment_routing_spec.lua` |
| **INV-11** | Inherited Ancestor Flag Persistence | `binding.visibility = "descendants"` | Inherited bindings copied into child `visible_options_by_name` | Inherited flag recognized across all descendant segments | `tests/invariants/inv_09_10_11_segment_routing_spec.lua` |
| **INV-12** | Compile-Time Shadowing & Alias Conflict Rejection | Rejection at `compiler.validate_graph` | Rejects duplicate aliases, child shadowing inherited options, and key collisions | N/A (Guaranteed at compile time) | `tests/invariants/inv_12_conflict_shadowing_spec.lua` |
| **INV-13** | Compile-Time Ambiguity Rejection | Rejection at `compiler.validate_graph` | Rejects non-final repeated positionals and inherited positionals | N/A (Guaranteed at compile time) | `tests/invariants/inv_13_ambiguous_grammar_spec.lua` |
| **INV-14** | Passthrough Delimiter (`--`) Termination | `node.passthrough_key` | Registers passthrough binding on node | Standalone `--` terminates all option and subcommand recognition | `tests/invariants/inv_14_15_passthrough_spec.lua` |
| **INV-15** | Exact Raw Passthrough Preservation | `ctx.passthrough` and `ctx.args[key]` array | Preserves raw tokens without string splitting or coercion | Retains verbatim token slice | `tests/invariants/inv_14_15_passthrough_spec.lua` |
| **INV-16** | Typed Context & Route Delivery | `ctx.args` and `ctx.route` | Prepares typed handler arguments | Populates validated dual-access keys and segment ownership tables | `tests/invariants/inv_16_typed_context_spec.lua` |
| **INV-17** | Lifecycle DAG Orchestration | `node.stages` | Builds topological lifecycle stage DAG with cycle detection | Executes stages in deterministic topological order | `tests/invariants/inv_17_18_lifecycle_process_spec.lua` |
| **INV-18** | Managed Process Explicit Lifecycle | `ProcessState`: `declared..reaped` | Process supervisor tracks PID and state | Supervised process state transitions tracked deterministically | `tests/invariants/inv_17_18_lifecycle_process_spec.lua` |
| **INV-19** | Distinct Signal Semantics (INT vs TERM) | `node.signals = { interrupt, terminate }` | Preserves distinct normalized signal handlers | SIGINT (2) and SIGTERM (15) dispatched independently | `tests/invariants/inv_19_signals_spec.lua` |
| **INV-20** | Composer Terminal Ownership | `ctx.composer` | Single Composer instance initialized per application run | All stdout/stderr output routed through active Composer | `tests/invariants/inv_20_21_composer_plain_spec.lua` |
| **INV-21** | Plain Mode Semantic Reduction | `Composer:render_plain(event)` | Zero ANSI escape codes emitted in plain mode | Progress ticks reduced to semantic milestones | `tests/invariants/inv_20_21_composer_plain_spec.lua` |
| **INV-22** | Control IPC Channel Isolation | Dedicated IPC queue in Context | Isolates control protocol events from stdout/stderr streams | Emits `process_ipc_send` semantic events on event bus | `tests/invariants/inv_22_control_ipc_spec.lua` |
| **INV-23** | Deterministic Scope LIFO Unwind | `ctx:scope(fn)` with `scope:defer(fn)` | LIFO execution stack in engine unwind runner | Executed on success, error, interrupt, and terminate | `tests/invariants/inv_23_deterministic_unwind_spec.lua` |
| **INV-24** | NDJSON Event Stream Parity | `Composer:render_json(event)` | All events emit standardized JSON protocol envelopes | 100% parity between human rendering and machine event stream | `tests/invariants/inv_24_ndjson_event_parity_spec.lua` |
| **INV-25** | Descriptive Metadata Non-Coercion | `binding.default` vs `schema.metadata.default` | Schema `metadata.default` is descriptive only; Clingy fallback explicit | Omitted arguments not populated from Valua default unless declared in Clingy | `tests/invariants/inv_04_05_06_valua_cardinality_spec.lua` |
| **INV-26** | Child Transition Precedence Over Positionals | Checked during non-option token dispatch | Verified that transition occurs if required positional minimums are met | Token consumed as positional only if positional debt exists | `tests/invariants/inv_09_10_11_segment_routing_spec.lua` |
| **INV-27** | Immutability of Normalized Command Graph | `ClingyCommandGraph` is read-only | `M.compile_router` reads from graph without mutating it | `c.reflect(app)` returns pure frozen graph | `tests/graph/snapshots_spec.lua` |
| **INV-28** | Permutation Invariance in Interspersed Mode | Interspersed grammar policy | Precomputes visible options for whole segment | Identical parsed output regardless of flag placement | `tests/properties/parser_properties_spec.lua` |
| **INV-29** | Cluster Equivalence | Short clusters policy | Precomputes cluster validator | `-xfv` produces exact identical `ctx.args` as `-x -f -v` | `tests/properties/parser_properties_spec.lua` |
| **INV-30** | Deterministic Multirun Parsing | Compiled Router lookup tables | Precomputed static tables reused across parses | 500 cyclic parse iterations produce bit-for-bit identical results | `tests/properties/parser_properties_spec.lua` |
