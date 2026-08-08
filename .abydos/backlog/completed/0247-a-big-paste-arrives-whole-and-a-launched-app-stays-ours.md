# A big paste arrives whole, and a launched app stays ours

`7f196912b` · 2026-08-04

Pasting a crash report into a terminal crawled, filled the pane with
mouse reports and needed the app restarted. Three faults, one after
another:

The pty's master is non-blocking, so a write big enough to fill its
buffer comes back saying "not now" — and the loop took that as "stop".
Most of a paste never left the app at all. What cannot go now waits and
is written when there is room.

Mouse motion was still being reported while that backlog drained. Those
reports say where the pointer was; sent late they say something untrue,
and they arrived in the middle of the paste, which is what filled the
screen with `35;127;37M`. Nothing advisory is sent while the program is
behind.

Then the fix itself deadlocked, twice, in ways worth naming: a write
source sharing the queue that reads meant waiting for room to write held
up reading what the program was sending back, so neither side could
move; and suspending that source when it had never been armed left it
suspended for good. It is a drain on a queue of its own now, waiting on
`poll`. 235 kB through a pty in 0.13 s, where before it hung.

And in the same breath, why a Swift app started by `make run` looked as
though it finished the instant it started: `open` hands the bundle to the
system and returns, so the make process really had. A goal ending in
`open <something>.app` now becomes a launch configuration for the binary
inside that bundle, with the goal's build step in front and lldb as its
debugger — so the app is a process of ours: output in the panel, stop
button working, debug starting it under lldb. Opening a URL or a folder
is not a launch and is left alone.
