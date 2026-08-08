# A branch's line starts at its newest commit

`4b31f8df7` · 2026-08-04

Every tip had a stub of line above its dot, arriving out of a history that
is not there. The row drew "what comes down into this commit's lane"
unconditionally, and for the newest commit of a line nothing does.

The layout knows which those are without being asked: a commit nothing was
waiting for is one nothing above leads to. That is the same test that
already decides whether to open a new lane, so it costs a bool.

The performance suite stops crying wolf as well. `viewportHighlightingIsFast`
measured one run of an 80-line viewport query against a 50ms bound, and
failed twice this week on a number that is 38ms when asked on its own — a
measurement of the machine as much as of the code, with the whole suite
running in parallel around it. Best of five now: noise only ever adds, so
the fastest run is the honest estimate of what the work costs, and a real
regression still moves the floor.
