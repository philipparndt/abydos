# 480. A fold budget measured in processor time still fails under load

**Numbered 480 and not 478, which `abydos-backlog new` chose**: it ran in 0476's
worktree, whose `main` predates 478 and 479, and reused a number that is taken.
The same collision 0476's own header records for 475. Nothing here depends on it.

Filed from 0476 rather than fixed there, because it is not that item's defect and
widening somebody else's performance bound is not a thing to do on the way past.

`PerformanceTests.foldComputationIsReasonableOnHugeFile` expects fold computation
over 100k lines to take under 10 seconds of **processor** time. Measured inside a
`make test` with fourteen spinners beside it, at 34 to 36 runnable threads per
core, it takes 10.4 to 11.1 — over by 4 to 11 per cent:

| | processor time | load | per core |
|---|---|---|---|
| red | 10.44 s | 362 | 36.2 |
| red | 11.09 s | 362 | 36.2 |
| red | 10.78 s | 126 | 12.7 |

**Green with nothing else running**: the whole suite passes in 32 s, 2498 tests,
no issues. So the bound is only reachable when the machine is busy.

The interesting part is that this is exactly the failure 0472 already fixed once,
in the same file, and processor time was the fix. The comment above
`foldingStateMapsLinesQuickly` says it: a wall-clock number inside `make test`
"was measuring the other three hundred and fifty suites", so the bounds were moved
to `cpuTime`. That was right and it is not sufficient here — processor time is not
load-independent either. Twenty threads per core compete for cache and memory
bandwidth, and the same arithmetic costs more cycles. So either

- the bound wants widening to whatever a busy machine actually costs, with the
  measurement written beside it, or
- this budget wants the treatment the third row suggests: it was already red at
  12.7 threads per core, which is inside the range `make test` produces on its
  own, so it may simply be too tight rather than load-sensitive.

Deciding which needs a sweep, which is why this is a written-down item and not a
one-line change.

## Ruled out

- **A change in the fold code.** Nothing in 0476 goes near it. The third row
  above is from 0476's *baseline* run, with the pty fix not yet applied.

## Steps

- [ ] Measure what the fold takes at 1, 10 and 35 runnable threads per core
- [ ] Decide between widening the bound and lowering the work, and say which here
- [ ] Write down here what was ruled out on the way
- [ ] `spec/` if any of this is behaviour rather than a test bound
