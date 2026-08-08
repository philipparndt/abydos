# Measure what the terminal actually costs

`470aa124a` · 2026-07-31

Two numbers, so a change to the terminal can be shown to have helped rather
than argued about. Both stand at roughly a fifth of what smooth output
needs.

TerminalThroughputTests feeds the emulator with nothing attached: plain log
output runs at 1.2 MB/s and a DOOM-fire frame — a truecolour change on every
cell, the whole screen repainted — at 0.9 MB/s. One fire frame at 100x40 is
76 KB, so 60fps wants 4.4 MB/s. That is about 12fps, with nothing drawn yet.

--bench-render times a full redraw of a fixed 40-row screenful, which is
what any change to the screen costs once it has to be shown again: 2.3 ms,
a ceiling near 430fps. Fixed rows rather than whatever height the panel was
left at, or the number means something different every run.

So the parser is the binding constraint by roughly five times, and the
renderer has room at 60fps. Worth knowing before deciding what to rewrite.
