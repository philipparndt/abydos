# Number the open backlog on from where the history ends

`f1d1eb4d0` · 2026-08-08

One sequence across the whole thing rather than two: `completed` runs
0001 to 0384, one per commit, and what is left to do carries on from
0385. A number then means the same kind of thing wherever it appears —
this is the 385th item in the project's life, it just has not happened
yet.

Which makes the shifting explicit rather than hidden. Landing a task
turns it into commits, those take the next numbers in `completed`, and
the open list is renumbered from the new end. The two have to be rebuilt
together or they collide, since `completed` numbers by commit ordinal and
knows nothing about the open list. Said plainly in the README, because a
scheme with a rule nobody wrote down is a scheme that will be broken by
somebody being reasonable.

The durable identifiers remain the commit hashes. Everything here is a
position in a queue.
