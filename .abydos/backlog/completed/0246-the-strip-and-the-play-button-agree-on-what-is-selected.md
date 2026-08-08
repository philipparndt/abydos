# The strip and the play button agree on what is selected

`dd4cf8cc5` · 2026-08-04

Choosing "make run" looked like it did nothing in a project that has
launch configurations of its own: the strip went on showing the first of
them — "make image" here — while the button would have run the goal. Two
places worked out what was selected, and they disagreed exactly where a
chosen name was not among the configurations, which is every time a
Makefile goal is chosen.

There is one answer now, `RunSelection.resolve`, and both read it.

Why the tests missed it, since they exist: they used a project with no
launch configurations at all, so the fallback they were meant to catch
had nothing to fall back to. The new ones use a project that has three,
and check that the name shown and the thing run are the same answer for
every combination of chosen, stale and deleted names.
