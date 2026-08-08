# Put the tmux switches in the order they depend on each other

`14332d51d` · 2026-08-04

Each one is only meaningful while the one above it is on: nothing
attaches to tmux, so nothing shows its windows as tabs, so there is no
second copy of its status bar to put away. They now read in that order —
attach, tabs, hide — and each is greyed while its parent is off. They
had been inserted at the same index one after another, which reversed
them, so the switch that depends on the tabs sat above them.

The rows can now describe themselves, so which of them is greyed is
something a run can print rather than something to squint at in a
screenshot.
