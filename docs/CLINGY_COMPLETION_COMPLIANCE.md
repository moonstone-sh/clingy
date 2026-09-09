# Completion compliance

Clingy resolves completion from the compiled command graph at tab time. Shell
backends only translate requests and render candidates.

The completion contract covers:

- structural command and alias completion;
- declaration-local `complete` providers;
- finite-choice discovery from schemas;
- same-token form captures with literal prefix preservation;
- captures following `c.next_token()`;
- explicit suppression through `c.none()`;
- filesystem directives for paths, files, and directories;
- isolated dynamic callbacks;
- Bash, Zsh, Fish, and PowerShell rendering.

Completion metadata may be placed on `c.arg`, `c.option`, `c.flag`, or
`c.capture`. Explicit metadata wins over schema-derived candidates.

The executable checks live in `tests/new_api_spec.lua`. The packaged shell
bridge gate lives in `tests/packaged-completion.sh`.
