# Ask the process whether it is running, rather than remembering

`910b06dc9` · 2026-08-04

Pressing stop left the tab green over `[process exited]`, and switching
tabs did not shake it off either: the tab's state was a flag set by an
exit handler, and whether that flag was ever set depended on which of
several handlers had been installed last.

The tab now asks the pane whether its process is alive. There is nothing
left to miss — no ordering, no chain, no flag to go stale — and pressing
stop refreshes the strip, since a program killed on purpose still stops
being a running one.
