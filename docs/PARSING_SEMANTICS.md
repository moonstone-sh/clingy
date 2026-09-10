# Parsing semantics

The parser walks one command segment at a time. Named declarations match their
aliases; positional declarations match in declaration order. `interspersed`,
`leading`, and `ordered` control where named declarations may appear.

Options accept only their declared value spellings. A value table may allow
attached separators, a detached next word, or direct adjacency. Forms then
parse structured values across byte offsets and argv boundaries.

Occurrence limits are enforced before a value is committed. A failed schema or
form branch cannot partially update `ctx.args`.

Child commands are literal, reserved edges. On a node that has children, its
positionals are required one-word prefixes and must be satisfied before a child
can be entered. `tool init development build` therefore parses `development`
at `init`, then takes the `build` edge. `tool init build` reports the missing
prefix instead of silently binding `build` as data. Optional and repeated
positionals are rejected on such a node.

`--` closes both option recognition and command routing. It lets a reserved
child spelling be supplied as positional data. `c.passthrough` or `c.tail`
can then capture or forward the remaining words.
