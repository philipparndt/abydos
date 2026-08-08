# A split that lasts

`13dd2eb8a` · 2026-08-02

Every activation threw the second pane away. Clicking a tab, opening a
terminal, starting a debugger — all of them went through one line that reset
the panel to a single pane, so a split lasted until the next thing happened.
That is why it worked once and then never again.

Whatever is shown now takes the column that has the focus, and the other
column goes on showing what it was showing. "Show One Only" is how a split
ends. The divider stays where it was put, too: changing what a column holds
rebuilds the split view, and a divider that jumps back to the middle every
time is one nobody can move.

Verified with the harness: a terminal beside the profiler, then a new
terminal opened and another tab clicked — still side by side.
