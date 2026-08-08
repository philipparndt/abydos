# Keep terminal history in a ring, and measure in release

`91768f776` · 2026-07-31

Scrollback was a plain array trimmed with removeFirst, so every line of
output past the limit moved the whole buffer down by one. A ring overwrites
the oldest entry instead. This did not move the benchmark — at five thousand
lines the shift is about five percent, lost in the noise — but it is O(1)
rather than O(n), so raising the limit no longer makes output slower, and
the structure is now covered by tests including the case that caught a bug
in it: a line pulled back out by a shrinking window left a gap that the next
append filled by evicting instead.

The benchmarks now say to run in release, because everything measured so far
was a debug build. A profile showed the time going almost entirely into
exclusivity checks, generic metadata lookups and unspecialised protocol
witnesses — all of which the optimiser removes. Debug numbers are roughly a
tenth of release and point at the wrong costs.

Measured properly, the parser work is worth 3x on plain output and 8.6x on
fire. It also means the parser was never what made the terminal feel slow:
even before any of it, release-mode fire parsed at 5.8 MB/s against the
4.4 MB/s a 60fps fire needs.
