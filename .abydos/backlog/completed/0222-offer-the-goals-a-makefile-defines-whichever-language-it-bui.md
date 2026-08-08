# Offer the goals a Makefile defines, whichever language it builds

`c74fc1df1` · 2026-08-03

`make dev` and `make run` were not offered in a Swift project, because the
menu only listed goals a Go debugger could be attached to. A project whose
Makefile says how to build and launch itself is exactly as runnable as one
that builds Go, and reading the Makefile and then pretending it said nothing
is worse than not reading it.

Every goal is offered now. The ones that can be debugged still become launch
configurations, with the build steps and the binary worked out; the rest run
as make runs them, in the terminal. Goals that clean, install or explain
themselves are left out — a run menu is a list of ways to start the thing
being worked on.

Read when the menu opens rather than taken from the background scan, which is
the other half of the bug: the scan finishes a moment after the project does,
and a menu opened before that showed nothing at all.

And a real one found on the way: installing a sidebar tool cleared the pane
references *after* building, throwing away the one that had just been made —
so the history pane existed on screen with nothing able to reach it, which is
why its folds did nothing. Cleared before building now.

    FOLD rows 12 -> 11
