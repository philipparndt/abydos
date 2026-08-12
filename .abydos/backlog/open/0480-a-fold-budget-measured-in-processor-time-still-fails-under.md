# 480. A fold budget measured in processor time still fails under load

**Numbered 480 and not 478, which `abydos-backlog new` chose**: it ran in 0476's
worktree, whose `main` predates 478 and 479, and reused a number that is taken.
The same collision 0476's own header records for 475. Nothing here depends on it.

Filed from 0476 rather than fixed there, because it is not that item's defect and
widening somebody else's performance bound is not a thing to do on the way past.

`PerformanceTests.foldComputationIsReasonableOnHugeFile` expects fold computation
over 100k lines to take under 10 seconds of **processor** time. It is a coin toss,
and the machine does not have to be busy for it to land badly — **the suite's own
parallelism is enough**. Measured, all three conditions:

| condition | processor time | verdict |
|---|---|---|
| the test on its own, six runs | 5.81, 5.83, 5.83, 6.02, 6.97, 7.15 s | green, margin 1.4–1.7× |
| inside `make test`, nothing else running | 10.10 s | **red**, by 1 per cent |
| inside `make test`, fourteen spinners (12–36 threads/core) | 10.44, 10.78, 11.09 s | **red**, by 4–11 per cent |

So it is neither a slow fold nor a busy machine. Alone the work has half again as
much room as it needs; what puts it over is the other three hundred and fifty-six
suites running beside it, and a fourteen-spinner load only adds a few per cent on
top of that. A full `make test` on an idle machine is already enough to make this
red about half the time.

This is exactly the failure 0472 already fixed once, in the same file, and
processor time was the fix. The comment above `foldingStateMapsLinesQuickly` says
so: a wall-clock number inside `make test` "was measuring the other three hundred
and fifty suites", so the bounds moved to `cpuTime`. **That was right and it is not
enough.** Processor time is not concurrency-independent — the same arithmetic costs
more cycles when thirty-odd threads are competing for cache and memory bandwidth,
and this measurement is 1.7× larger inside the suite than outside it. `cpuTime`
removed the scheduling and left the contention.

So the sweep 0472 did for the three bounds in that file wants doing again with the
suite running, because "on its own" is the condition none of these tests are ever
actually measured in. `elapsed < 10.0` against a real 10.10 is not a budget, it is
a coin. Whether the answer is a wider number, a smaller input, or a bound that
tolerates the suite explicitly is the thing to decide — with the numbers above
written beside whatever is chosen, since the next person will otherwise re-measure
all three conditions.

## Ruled out

- **A change in the fold code, or anything in 0476.** Nothing in that item goes
  near folding — it is all `PseudoTerminal`. And the 10.78 s row is from 0476's
  own *baseline* run, taken before its fix existed.
- **A busy machine being necessary.** It is red inside a plain `make test` on an
  idle machine, at 10.10 s. Fourteen spinners add only a few per cent on top.
- **The fold itself being too slow.** On its own it is 5.8 to 7.2 s against a 10 s
  bound, six runs out of six.

## Steps

- [x] Measure the fold on its own, inside `make test`, and inside `make test`
      under load — the three conditions above
- [ ] Decide between a wider bound, a smaller input, and a bound that says out
      loud that it is measured inside the suite; say which here and why
- [ ] Sweep the other two bounds in `PerformanceTests` the same way, since they
      were set by the same reasoning
- [ ] Write down here what was ruled out on the way
- [ ] `spec/` if any of this turns out to be behaviour rather than a test bound
