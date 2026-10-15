# Built CLI format (`clingy.built.v1`)

`clingy.build` writes a CLI as an ordinary Lua module. This document is the
public contract for that module, so tools other than `clingy.runtime` (editor
plugins, documentation generators, completion generators, bundlers) can read
it. See [BUILD_TIME.md](BUILD_TIME.md) for how to produce and run one.

## The module

Requiring the module returns a table:

| Field | Type | Meaning |
| --- | --- | --- |
| `format` | `"clingy.built.v1"` | Format and major version. Readers must reject other values. |
| `source` | string | Module name of the declaration the build read. Informational. |
| `graph` | table | The command graph (`clingy.command-graph.v0`, [COMMAND_GRAPH.md](COMMAND_GRAPH.md)), with the changes below. |
| `schemas` | array of `{ schema, info }` | Every schema the graph refers to, once each, with its precomputed inspection. |

Loading the module runs code: it requires the modules that hold handlers,
schemas and completion callbacks. A tool that only needs the structure must
still be able to load those modules (or stub `require`).

## Differences from the in-process graph

- **No `decl_map`.** Nodes built by `c.create` map declaration tables to
  bindings, so `ctx:get(decl)` can look up a declaration object. A built CLI
  has no declaration objects, so the field is absent. Handlers read
  `ctx.args.<key>` or `ctx:get("<key>")`; the generated args module (below)
  provides types and key names.
- **Functions are module exports.** Every function in the graph (node
  `handler`, `signals` entries, `stages` callbacks, `dynamic` completion
  callbacks) is the value of `require("<module>").<export>` for a module the
  declaration required. Its identity is the same as in that module.
- **Schemas are the same objects or exact copies.** A schema is either an
  export (`require("<module>").<export>`) or, for inline Valua schemas of a
  supported shape, a new object built from Valua's individual modules
  (`require("valua.schemas.string")()`). The build accepts a copy only if
  `valua.reflect` of the copy equals `valua.reflect` of the original. The same
  schema object is the same value everywhere it appears in the graph.
- **Completion providers are recreated** from their kind and data through
  `clingy.completion.providers` (`values`, `file`, `path`, `directory`,
  `none`, and `dynamic` with an exported callback).
- **Shared tables stay shared.** A table referenced from several places (for
  example a passthrough binding and the node's `end_capture`) is one table.

Everything else is plain data: strings, numbers, booleans, and tables
without metatables.

## `schemas[i].info`

The result of `clingy.adapter.inspect_schema(schema)` at build time:

| Field | Type | Meaning |
| --- | --- | --- |
| `kind` | string? | `"string"`, `"integer"`, `"number"`, `"boolean"`, `"picklist"`, or another Valua node kind. Drives token coercion. |
| `options` | array? | Allowed values for picklists and literals. |
| `description` | string? | From schema metadata. |
| `default` | any? | From schema metadata; descriptive only. |

`clingy.runtime.load` registers these with `clingy.adapter.preload_inspection`,
so parsing never reflects schemas at run time.

## Stability

- Adding fields to the top-level table or to `info` is compatible within v1.
  Readers must ignore fields they don't know.
- Changing the meaning of an existing field, removing one, or changing the
  graph format is a new major version (`clingy.built.v2`).
- Output is deterministic: the same declaration and modules produce the same
  text, with keys sorted. It is safe to commit and diff.

## The args module

Next to the built module, `clingy.build` writes `<module>.args` (unless
`args_module = false`). It returns, per command, a table from result key to
the same key (`args.root.name == "name"`), and declares LuaLS classes:

- `<args>.<command>.values`: one field per result key visible in that
  command (its own bindings and inherited ones), typed from the schema.
- `<args>.<command>.context`: `clingy.Context` with `args` typed as the
  values class. Annotate handlers with `---@param ctx <args>.<command>.context`.
- `<args>.<command>`: the key table, typed `clingy.Binding<T>`.

Command names: `root` for the root, otherwise the path below the root with
non-identifier characters replaced by `_` (`remote add` is `remote_add`).
The build fails if two commands map to the same name.

Types: flags are `boolean`; passthrough and end captures are `string[]`;
other bindings take the schema's type (`string`, `integer`, `number`,
`boolean`, a union of literal options, `table` for forms, `string` without a
schema, otherwise `any`), as `(T)[]` when repeated, and with `|nil` unless
required or defaulted.
