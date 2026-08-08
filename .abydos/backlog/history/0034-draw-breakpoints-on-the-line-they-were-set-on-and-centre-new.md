# Draw breakpoints on the line they were set on, and centre new windows

`c3bebea90` · 2026-07-31

Breakpoints are stored the way a debug adapter numbers lines, from 1.
They were handed to the view unchanged, and the view draws rows, which
start at 0 — so every marker appeared one line below the line it was set
on. The execution-line marker beside it had always converted; breakpoints
did not.

New windows are centred rather than placed at AppKit's bottom-left
default. The autosaved frame still wins where there is one, and a second
window cascades from the first instead of landing exactly on top of it.
