# The play button comes back pointing where it was left

`06d625ad6` · 2026-08-04

Reopening a project put the run control back to nothing, so the thing you
had been running all week was three clicks away every morning — and the
first of those clicks, on a play button pointing at something else, runs
the wrong thing.

Kept in `.ideai/session.json`, which is where what-was-open for this
project already lives. The name only: *what* to run belongs to the project
and is in `.ideai/run` for everyone, while *which of them you picked* is
this window's.

Written as the selection changes rather than at quit, for the reason the
open files already are — a window that never gets to say goodbye, a crash
or a force quit, should still come back to what it was doing.

That turned up a way to lose the rest of it. Every tab change wrote the
editor's half of the session over the whole file, so the terminals, the
panel and the subproject were dropped and only put back by whatever wrote
next. Merged now, rather than written over.
