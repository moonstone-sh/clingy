# Clingy Shell Completion Protocol Specification

## 1. Abstract & Scope

This document specifies the normative machine protocol between shell completion wrappers (bridges) and the executable application binary built with Clingy.

The protocol defines:
1. The invocation arguments of the hidden endpoint (`--__clingy-complete`).
2. Candidate serialization formats per shell.
3. Directive bitmasks controlling shell completion behavior.
4. Error suppression and stream isolation rules.

---

## 2. Hidden Silent Endpoint

Shell bridges query completions by executing the application binary with the `--__clingy-complete` flag at index 1 of the command line:

```bash
<binary> --__clingy-complete --shell=<SHELL> --index=<INDEX> -- <WORDS...>
```

### Argument Specification

| Argument | Type | Required | Description |
|---|---|---|---|
| `--__clingy-complete` | Flag | Yes | Signals the application to divert immediately into the completion engine. |
| `--shell=<SHELL>` | String | Yes | Target shell dialect. Must be one of: `bash`, `zsh`, `fish`, `powershell`. |
| `--index=<INDEX>` | Integer | Yes | 1-based index into the `<WORDS...>` vector representing the cursor token. |
| `--` | Separator | Yes | Terminates protocol control flags. All following tokens represent `<WORDS...>`. |
| `<WORDS...>` | String[] | Yes | The command-line words as tokenized by the calling shell. |

### Execution Guarantees
- **Early Interception**: The endpoint is processed inside `App:run()` before application lifecycle stages, user hooks, or output composers are initialized.
- **Zero Exit Pollution**: The process exits with status code `0` regardless of validation errors in user code or missing arguments.
- **Clean Standard Streams**: Normal application output (stdout/stderr) is never produced on this path. Only protocol completion payloads are written to standard output.

---

## 3. Directive Flag System

Completion responses return an integer bitmask combining one or more directives:

```
+-------------------------------------------------------------+
| Bit 0 (1): DIRECTIVE_FILENAMES   - Shell filename fallback   |
| Bit 1 (2): DIRECTIVE_DIRECTORIES - Shell directory fallback  |
| Bit 2 (4): DIRECTIVE_NO_FILES    - Inhibit file completion   |
| Bit 3 (8): DIRECTIVE_NO_SPACE    - Omit trailing space       |
+-------------------------------------------------------------+
```

### Bitwise Directives

| Constant | Value | Description |
|---|---|---|
| `DIRECTIVE_DEFAULT` | `0` | Standard candidate list. Shell may fall back to files if candidates are empty (shell-dependent). |
| `DIRECTIVE_FILENAMES` | `1` (`1 << 0`) | Instructs the shell to perform filename completion on the current token. |
| `DIRECTIVE_DIRECTORIES` | `2` (`1 << 1`) | Instructs the shell to perform directory name completion only. |
| `DIRECTIVE_NO_FILES` | `4` (`1 << 2`) | Explicitly forbids the shell from falling back to default filesystem path completion. |
| `DIRECTIVE_NO_SPACE` | `8` (`1 << 3`) | Tells the shell not to append a trailing space (e.g. for directory paths or inline `--flag=`). |

---

## 4. Shell Candidate Stream Formats

The output rendered to stdout varies by target shell dialect to align with each shell's native completion primitives:

### 4.1. Bash

Bash consumes candidate lines followed by special directive instructions read by the bash completion wrapper:

```text
candidate1
candidate2
:directive:filenames
:directive:nospace
```

- Each candidate is printed on its own line.
- Descriptions are omitted (Bash native programmable completion does not support descriptions in `COMPREPLY` without custom fzf/readline wrappers).
- Trailing directives are prefixed with `:directive:`:
  - `:directive:filenames` -> triggers `compopt -o filenames`
  - `:directive:dirnames` -> triggers `compopt -o dirnames`
  - `:directive:nospace` -> triggers `compopt -o nospace`
  - `:directive:nofiles` -> triggers `compopt +o default`

### 4.2. Zsh

Zsh parses candidate values paired with descriptions using a colon separator (`:`):

```text
candidate1:Description for candidate 1
candidate2:Description for candidate 2
:directive:filenames
:directive:nospace
```

- Format: `<value>:<description>`
- If no description is present, only `<value>` is output.
- Directives are processed by the Zsh bridge to dynamically pass `-f` (filenames), `-S ""` (no space), or custom tags to `compadd`.

### 4.3. Fish

Fish consumes tab-delimited values and descriptions:

```text
candidate1\tDescription for candidate 1
candidate2\tDescription for candidate 2
```

- Format: `<value>\t<description>`
- If no description is present, only `<value>` is printed.
- Fish native completion scripts use the output directly via `complete -c <cmd> -f -a "(<cmd> --__clingy-complete ...)"`.

### 4.4. PowerShell

PowerShell uses tab-delimited lines containing value and ToolTip:

```text
candidate1\tDescription for candidate 1
candidate2\tDescription for candidate 2
```

- The PowerShell completer script wraps each line into a `[System.Management.Automation.CompletionResult]::new($value, $value, 'ParameterValue', $tooltip)`.

---

## 5. Token Extraction & Boundary Handling

### Trailing Space Detection
When a user presses `<TAB>` after typing a word followed by space (e.g. `myapp run `):
- In Bash: `COMP_CWORD` points past the last typed token, and an empty string `""` represents the new token.
- In Zsh/Fish: An empty string is passed as the final word.
- In Partial Parser: The parser recognizes an empty token as a request for all available subcommands or next positional candidates.

### Inline Equals (`--opt=val`)
When the cursor is on an argument containing `=`:
- The parser splits the token at the first `=`.
- The option name before `=` is checked against the Command Graph.
- If valid, the focus shifts to `FOCUS_OPTION_VALUE` targeting the text after `=`.
- The directive bit `DIRECTIVE_NO_SPACE` is set to keep the cursor adjacent to the value.

### Passthrough Boundary (`--`)
When a standalone `--` is encountered in `<WORDS...>` before `--index`:
- The parser enters `FOCUS_PASSTHROUGH`.
- Subcommand, option, and argument candidates are immediately suppressed.
- Shell falls back to filename completion unless a passthrough provider is explicitly configured.
