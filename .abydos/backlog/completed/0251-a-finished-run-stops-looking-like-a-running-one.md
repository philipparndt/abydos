# A finished run stops looking like a running one

`b0f90916e` · 2026-08-04

The tab stayed green over `[process exited with status 129]`. The panel
learns a process has gone from the terminal's exit handler — that is what
sets `hasExited`, and so what takes the green off the tab — and the run
path replaced that handler with one of its own rather than adding to it.
So the titlebar knew the run had ended and the tab never did.

Both are called now: the tab goes dark with a stopped mark, the titlebar
says how it went.
