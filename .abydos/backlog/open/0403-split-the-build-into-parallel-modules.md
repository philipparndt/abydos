# 403. Split the build into parallel modules

The build is slow enough to hold work up. AbydosApp is one target of some
hundred and fifty files, so every change recompiles all of it, and AbydosKit
is nearly as large.

Worth deciding first what the seams actually are rather than splitting by
folder. Candidates that look like real boundaries: the terminal (emulator,
pty, tmux, graphics — already almost self-contained), the editor and its
language support, git, and the run/debug machinery. The settings and theme
sit under all of them and would have to go somewhere they can be depended on
without pulling the rest in.

Measure before and after with the same clean build, and say the numbers.

## Decided

**Measure, split the terminal, measure again.** Time a clean build first; pull
out only the terminal — emulator, pty, tmux, graphics, already nearly
self-contained and the largest thing nothing else needs to know about — then
time it again. If that does not move the number, that is the answer about the
whole plan, learned cheaply.

Before starting: say where `Theme` and `Settings` live. Everything depends on
them, so they belong in a base module underneath, and nothing may depend
upward. If that cannot be stated, the split is not ready.

Worth timing at the same time, since it may be most of it: whole-module
optimisation and the tree-sitter grammars rebuilding.

---

Previously numbered 36, 392.
