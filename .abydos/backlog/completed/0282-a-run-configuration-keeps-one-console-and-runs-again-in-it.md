# A run configuration keeps one console, and runs again in it

`7546ae602` · 2026-08-05

Running the same thing five times left five consoles behind, each holding a
finished program, and the one worth reading was whichever happened to be on
top. The tab strip filled with tabs called `make`, and closing them one by one
was a chore that arrived after every session of work.

A run console now belongs to the thing it is the console of — this launch
configuration, this make step, `go test` in this module — and running that
thing again takes over the tab the last run used, in the place the last run
left it. Somebody who has just pressed Run is already looking at where the
answer will appear.

Whatever the previous run was still doing when the next one starts, it was the
previous run of this same thing, and starting again is what "run it again"
means; it is stopped rather than left going in a tab behind the new one. A
console with no such identity — an agent session, a one-off command — still
gets a pane of its own every time, because it is not the console of anything
that can be run twice.
