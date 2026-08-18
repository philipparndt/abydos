## Context

Two different mistakes share one cause: a number chosen while watching a test run on
its own, in a suite that never runs anything on its own.

- A **sleep** bets that 200ms is longer than the work takes. Under the suite's
  parallelism — the Makefile already records this machine sitting at load 35–40
  during `make test`, and it was far above that with three agents building — the
  assertion arrives before the message does.
- A **processor-time bound** bets that contention is not part of the measurement. It
  is: 5.8–7.2 s alone, 10.10 s inside the suite, for the same work.

The two want different fixes and are the same item because fixing one and not the
other leaves the suite exactly as untrustworthy.

## Goals / Non-Goals

**Goals:**

- A test that waits for something in this process synchronises on it, and cannot pass
  or fail by timing.
- A performance bound states the condition it was measured in, with numbers.
- The line between the two kinds of `Task.sleep` is drawn deliberately and written
  down, not left to whoever next reads a red run.

**Non-Goals:**

- Removing all 45 sleeps. A live test waiting on a container starting may genuinely
  have nothing to await, and forcing one would trade a flake for a hang — strictly
  worse, because a hang costs the whole suite.
- Making performance tests unconditionally green. A bound that cannot go red is not
  a bound.
- Changing how `make test` parallelises. The parallelism is the point of it.

## Decisions

**Synchronise on the callback, not the clock.** A continuation the `onMessage`
handler resumes, or an `AsyncStream` the test reads one element from — whichever the
tree already has for this. Then the assertion cannot run early and the test takes
microseconds.

**A shared helper, with its timeout as a failure bound.** If a dozen tests want
"wait until this closure has been called once, or fail", that belongs in one place
with a generous timeout. The distinction is the whole point and belongs in its
comment: a sleep's duration is the *expected* wait, so it is a guess that must be
right; a helper's timeout is only reached when the test is going to fail anyway, so
it can be generous without costing anything in the passing case.

**In scope: the in-process waits.** Where the thing being waited for is in this
process and could be awaited or signalled, it should be. Those are the cheap and
certain wins. Every sleep left in place gets a sentence saying what it is standing in
for, so the next reader can tell a considered one from an unexamined one.

**Performance bounds are re-measured with the suite running.** `elapsed < 10.0`
against a real 10.10 is not a budget, it is a coin. Three ways out and the choice
wants stating rather than assuming: a wider number, a smaller input, or a bound that
says out loud it is measured inside the suite. A smaller input is worth real
consideration — the claim "folding 100k lines is not accidentally quadratic" survives
a smaller corpus, and a cheaper test is one that can stay in the suite.

**Whatever is chosen, the three conditions are written beside it.** Without them the
next person re-measures all three, which is most of the cost of this item.

## Risks / Trade-offs

- **A helper that hangs instead of failing** → Its timeout must fail the test, not
  return quietly. A hang in a parallel suite is worse than a flake because it costs
  the whole run.
- **Widening a bound until it means nothing** → Which is why the numbers go beside
  it. A bound with its measurement conditions recorded can be judged later; a bound
  that was simply doubled cannot.
- **Converting a live test's sleep and getting a hang** → Mitigated by keeping them
  out of scope by default and naming why each stays.
- **The suite's load is itself a variable** → The Makefile's comment around
  `make bounds` already argues that timing assertions inside `make test` cannot tell
  the harness's penalty from the effect they mean to detect. Point at that argument
  rather than restating it, and consider whether the fold bound belongs in
  `make bounds` rather than `make test` at all.

## Open Questions

- Which of the 44 other sleeps are in-process? The count is known; the split is not.
- Does the fold test belong in `make test` or in `make bounds`? That may be the real
  answer to 0480, and it is not the same as widening a number.
