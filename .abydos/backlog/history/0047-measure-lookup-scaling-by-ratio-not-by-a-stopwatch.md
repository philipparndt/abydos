# Measure lookup scaling by ratio, not by a stopwatch

`ea0d4f5b2` · 2026-07-31

lineLookupsAreLogarithmic asserted a wall-clock limit, so it tested the
machine's current load as much as the rope: it passed alone and failed
under a parallel run, twice in one session. The claim it exists to make
is about growth, so it now times the same 10k lookups against a 2k-line
and a 200k-line file and compares them.

A hundredfold more lines costs 1.3–1.4x, which is the logarithm doing
its job; linear would be a hundredfold. The bound is 10x, far enough
above the real figure to absorb a loaded machine and far enough below
linear to still fail if the structure regresses.
