# Completion protocol

Shell bridges invoke the application through a hidden endpoint:

```text
<binary> --__clingy-complete <shell> <words...> --cword=<index>
```

`words` is the command line through the cursor, including the executable. An
empty active word may be omitted as long as `cword` points one position past
the supplied words. `cword` is 1-based. Bridges remove shell quoting from
completed words and preserve the active word's insertion prefix.

The endpoint runs before parsing, handlers, lifecycle stages, and presentation.
Protocol version 2 uses typed, tab-separated records:

```text
V<TAB>2
D<TAB>filenames,nospace<TAB>file<TAB>--config=<TAB>lua,luax
C<TAB>--config=src/main.lua<TAB>Lua entry point
```

- `V` declares the protocol version.
- `C` carries an insertion value and optional description.
- `D` carries directives, filesystem kind, replacement prefix, and allowed
  extensions. `-` means the field is absent.

The directives are `filenames`, `dirnames`, `nofiles`, and `nospace`.
Filesystem kind is `path`, `file`, or `directory`.

Colons, spaces, quotes, and backslashes are ordinary field content. Candidate
values cannot contain NUL, tab, CR, or LF because those bytes delimit records;
descriptions normalize those control characters to spaces.

`App:complete({ words = ..., cword = ... })` returns the structured response
before rendering. `App:completion_script` and
`c.completion.completion_script` generate the shell bridges.
