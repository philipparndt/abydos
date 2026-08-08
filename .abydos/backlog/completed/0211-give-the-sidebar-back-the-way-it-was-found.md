# Give the sidebar back the way it was found

`06a5d28e1` · 2026-08-03

Looking at something over a maximised terminal used to change what the
sidebar was showing, so leaving full screen came back to whatever had been
borrowed last — and to a strip that marked nothing at all, since the selection
had been cleared on the way in and nobody put it back.

A popover borrows a tool now; it does not change what the sidebar is showing.
Leaving full screen puts that tool up again, hands the tree back its titlebar
inset, and says which one it is.
