# 416. The performance suite asserts wall clock in a debug build

`PerformanceTests.foldComputationIsReasonableOnHugeFile` fails when the machine
is busy and passes when it is not. Measured on one machine in one morning, the
same code every time:

    alone                                     7.1 s
    in the full suite                        10.2 s   ← fails, bound is 10.0
    with four agents building beside it  12 – 32 s

It failed four times in six full runs today, and each failure cost a re-run to
find out it was nothing. `reparseCostJustifiesBackgroundQueue` is the same
shape with more headroom: 80 ms per reparse alone, 183 ms under load, against a
200 ms bound.

**Why this cannot be fixed by choosing a better number.** The suite runs its
tests in parallel, so the work is competing with whatever else is running, and
the number it is compared against has to hold for the worst arrangement. Fold
takes seven seconds alone; the bound would have to be thirty or so to be quiet,
and a bound of thirty catches nothing — it would take a fourfold regression to
trip it.

And the measurement is not the one anybody cares about. This is a debug build,
so it is measuring unoptimised tree-sitter and unoptimised Swift; `make perf`
already exists and runs the same suite in release, which is where a number
means something about the app somebody uses.

## Decided, and done

**Kept in the suite, measuring processor time rather than wall clock.** The two
that were flapping now use `cpuTime`, which was already in the file and already
had the answer to the objection below: it reads `CLOCK_THREAD_CPUTIME_ID`, so
it measures the thread doing the work and not the machine around it. That is
the difference from `getrusage`, which reports the whole process and failed the
other way round.

The bounds did not move. Fold now measures 6.3 seconds of processor time
against its 10, where wall clock gave 7.1 alone and 10.2 under the suite;
reparse measures 53ms against its 200, where wall clock gave 80 alone and 183
under load. Both have real headroom for the first time, and the headroom means
something about the code.

The other two were not chosen: `make perf` in release keeps the numbers a user
would recognise, but only when somebody runs it, and serialising the suite
would not have helped against four agents building beside it.

## Worth deciding

- **Move the assertions to `make perf`**, and have the debug run print the
  numbers without comparing them. Keeps the timings visible in every run — they
  are useful to read — and puts the pass/fail where the measurement is real.
  The cost is that a regression is only caught when somebody runs `make perf`
  or CI does.
- **Keep them in the suite but measure CPU rather than wall clock.**
  `PipeDrainTests` says at the top why that was rejected once already:
  `getrusage` reports the whole process, so it passed alone and failed in the
  suite — the opposite failure, and worse.
- **Serialise the performance suite** with `.serialized` so it at least does not
  compete with itself. Does nothing about the four agents.

The first is the recommendation. Whichever is chosen, the numbers above should
go in the entry that changes it, because the next person to widen a bound will
want to know what it was widened from and why.

---

Its number is where it sits in the queue, not what it is worth doing next.
