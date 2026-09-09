# Parsing semantics

The parser walks one command segment at a time. Named declarations match their
aliases; positional declarations match in declaration order. `interspersed`,
`leading`, and `ordered` control where named declarations may appear.

Options accept only their declared value spellings. A value table may allow
attached separators, a detached next word, or direct adjacency. Forms then
parse structured values across byte offsets and argv boundaries.

Occurrence limits are enforced before a value is committed. A failed schema or
form branch cannot partially update `ctx.args`. `--` begins passthrough capture
when the node declares `c.passthrough` or `c.tail`.
