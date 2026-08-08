# Let mode and status queries through the private-sequence guard

`901d964fc` · 2026-07-31

The guard added in the previous commit returned for any private-
introduced sequence whose final was not h, l or c. DECRQM arrives as
`CSI ? Pa $ p`, so it was dropped — and its handler checks for the `?`
itself, which made that handler unreachable. tmux and modern shells
probe synchronised output (mode 2026) this way and wait for the answer;
its own comment says silence "leaves the program waiting". `CSI ? 6 n`
was dropped the same way.

Both are allowed through now, and the allowed finals are a named set
with the contract written down: a final belongs there once its handler
inspects the introducer itself. Leaving one out silently drops a query
the sender is blocking on, which is worse than the mis-parse the guard
prevents.

DECXCPR also now carries the `?` back in its reply, so a sender that
issued both forms can tell them apart. It previously answered with the
plain CPR format.

Found by the agent review, which also noted there was no test covering
DECRQM — hence none of this failed. There are now tests for both
queries and for the guard's contract in both directions.
