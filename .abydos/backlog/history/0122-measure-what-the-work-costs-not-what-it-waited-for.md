# Measure what the work costs, not what it waited for

`75b4720e9` · 2026-08-01

The viewport benchmark kept failing at 66ms against a 50ms budget while
measuring 38ms alone. Best-of-five did not help, because the whole suite runs
alongside it and every round is slowed by the same neighbours: the number was
a fact about the machine, not about the code.

Both benchmarks measure processor time now. It is what changes when the code
changes, and it holds steady across repeated full runs — 0.9ms per keystroke
against a 2ms budget, 44ms for a viewport query against 50 — where wall-clock
swung by three times depending on what else was running.
