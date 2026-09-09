# Completion protocol

Shell bridges invoke the application through a hidden endpoint:

```text
<binary> --__clingy-complete <shell> <words...> --cword=<index>
```

`shell` is `bash`, `zsh`, `fish`, or `powershell`. `words` includes the binary
name and the current, possibly empty, word. `cword` is the 1-based index of the
current word. The generated bridges translate their shell's cursor convention
to this contract; Bash therefore adds one to `COMP_CWORD`.

The endpoint runs before parsing, handlers, lifecycle stages, and presentation.
It writes only completion records to standard output and returns zero when a
provider cannot produce candidates.

Candidate records are line-oriented:

- Bash: value only.
- Zsh: `value:description`, with colons escaped in descriptions.
- Fish and PowerShell: `value<TAB>description`.

An optional `:directive:` record precedes candidates. The supported directives
are `filenames`, `dirnames`, and `nospace`. They request shell-native file or
directory completion and suppress the trailing space where appropriate.

`App:complete({ words = ..., cword = ... })` uses the same 1-based word model.
It returns the structured response before shell rendering. `App:completion_script`
and `c.completion.completion_script` generate the bridges.
