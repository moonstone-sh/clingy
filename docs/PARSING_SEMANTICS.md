# Clingy Parsing Semantics & Token Grammar (`clingy/parser.lua`)

## 1. Multi-Segment Evaluation Model

Clingy parses argv across a sequence of **Command Segments** defined by the command topology:

```text
               argv: [ "meteorite", "init", "development", "instant", "-vn", "--", "extra" ]
               
Segment 1: "root"      [ meteorite ]
Segment 2: "init"      [ init, development ]
Segment 3: "instant"   [ instant, -vn ]
Passthrough:           [ extra ]
```

Each segment maintains its own:
- Positional argument cursor (`positional_cursor`).
- Ordered grammar cursor (`ordered_cursor`).
- Positional consumption count (`positionals_consumed`).
- Visible options and flags table (composed of local declarations + inherited ancestor declarations).

---

## 2. Token Classification & Processing

For each token in `argv`:

```text
                      Is '--' token?
                        │          │
                     Yes│          │No
                        ▼          ▼
             Begin Passthrough   Is passthrough active?
                                   │               │
                                Yes│               │No
                                   ▼               ▼
                            Capture Raw    Is option-like (-* / --*)?
                                                   │           │
                                                Yes│           │No
                                                   ▼           ▼
                                            Parse Option   Match Child or
                                              or Cluster     Positional
```

### 2.1 Option & Flag Parsing
1. **Long Form & Short Form Matching**: Looked up in `node.visible_options_by_name`.
2. **Attached Values (`--key=val` / `--key:val`)**: Both spellings (and their short aliases, such as `-k=val`) are extracted and passed directly to the schema validator.
3. **Detached Values (`-c val` / `--config val`)**: The parser advances `i = i + 1` to consume the next token from `argv`. If the next token is missing or is `--`, a compile/runtime parsing error is raised (`"Option requires a value"`).
4. **Flag Invariant**: Flags with attached values (`--flag=true` or `--flag:true`) are rejected. Flags always record boolean `true` and consume 0 argv tokens; a following detached token remains available to positional parsing.
5. **Exact Alias Precedence**: A declared alias containing `:` or `=` is matched
   exactly before attached-value splitting, preserving legacy aliases such as
   `--legacy:flag`.

### 2.2 Short Flag Clustering (`c.short_clusters()`)
When enabled on a node:
- Single-dash tokens with length $\ge 2$ matching `^%-[a-zA-Z0-9]+$` (e.g. `-xvf`) are decomposed into individual characters (`-x`, `-v`, `-f`).
- Every character in the cluster MUST be a visible flag consuming 0 values.
- If any character corresponds to an option taking a value or an unknown token, clustering is rejected and standard option lookup is evaluated.

### 2.3 Composed Positional Tokens (`c.compose(...)`)
`c.compose` consumes one positional argv token through its node-declared fixed
pattern. It is evaluated only when that positional slot is selected; Clingy
does not split all ordinary positionals on `:` or `=`. The matcher is anchored
to the complete token, validates each labelled capture through the normal
schema adapter path, and publishes only the labels into the owning route
segment and `ctx.args`.

Pattern separators match their punctuation plus surrounding whitespace by
default. `{ trim = false }` leaves that whitespace in the adjacent capture.

See the runnable [`advanced-grammar` example](../examples/advanced-grammar/) for
composed captures, repeated `c.define` records, and end forwarding together.
The compiler rejects capture pairs without an intervening fixed fragment, so
the parser never guesses a boundary between two variable fields.

---

## 3. Grammar Ordering Modes

Clingy supports 3 distinct parser ordering modes configured per node segment:

### 3.1 `interspersed` (Default)
Options and flags may appear in any position relative to positional arguments:
```bash
mycli -f file1.txt -m fast file2.txt
```
All options are recognized and positionals are consumed in sequence.

### 3.2 `leading`
Options and flags MUST precede positional arguments within the segment:
```bash
mycli -f -m fast file1.txt file2.txt   # VALID
mycli file1.txt -f file2.txt          # ERROR: -f treated as positional or rejected
```
Once positional argument consumption begins, option recognition terminates for that segment.

### 3.3 `ordered`
Strict pipeline order: declarations must appear in the exact order declared in the node:
```lua
c.node({
  c.ordered(),
  c.flag("--prepare"),
  c.arg("src", v.string()),
  c.flag("--commit"),
  c.arg("dst", v.string()),
})
```
Any token appearing out of sequence raises an `Ordered grammar error`.

---

## 4. Child Command Transition vs Positional Precedence (Section 22)

When a non-option token matches a child command name or alias, Clingy evaluates **Transition Precedence**:

```lua
local can_transition = false
if current_node.child_names_map[token] then
  local req_satisfied = true
  for _, arg_decl in ipairs(current_node.args) do
    local cnt = occurrence_counts[arg_decl] or 0
    if cnt < (arg_decl.occurrence.min or 1) then
      req_satisfied = false
      break
    end
  end
  if req_satisfied then
    can_transition = true
  end
end
```

### Invariant Guarantee:
1. **Transition Wins**: If all required positional arguments on the active segment have satisfied their minimum occurrence count (`occurrence.min`), the token triggers a child command segment transition.
2. **Positional Debt Wins**: If the active segment still has unmet required positional arguments, the token is consumed as a positional argument on the current segment, even if its string value matches a child command name.

---

## 5. Passthrough Delimiter (`--`)

1. Encountering standalone `--` immediately terminates all option and subcommand recognition.
2. All subsequent tokens are captured verbatim without trimming, shell splitting, or character normalization into `ctx.passthrough` and `ctx.args[passthrough_key]`.

---

## 6. Valua Lexical Adaptation (`clingy/adapter.lua`)

CLI argv tokens are raw strings. Clingy uses Valua schema reflection to perform lexical coercion before validating constraints:

| Valua Reflected Type | Coercion Logic |
|---|---|
| `string` / `picklist` | Identity (passed as-is) |
| `boolean` | `"true"`, `"1"`, `"yes"`, `"on"` $\to$ `true`; `"false"`, `"0"`, `"no"`, `"off"` $\to$ `false` |
| `integer` | Coerced via `math.tointeger(token)` |
| `number` | Coerced via `tonumber(token)` |

After lexical coercion, the adapted value is passed to Valua's Standard Schema validation (`~standard.validate(val)`), ensuring full schema rule enforcement (regex patterns, ranges, custom refinements) without duplicate code in the CLI parser.
