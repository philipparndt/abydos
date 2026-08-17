## Why

Two tests are red about half the time and neither is about the code it names. Both
are timing bets, and what settles the bet is **the suite's own parallelism** rather
than a busy machine.

**`LSPFramingTests.readsAMessageArrivingInPieces`** (backlog 0530) failed twice in a
row during the 0529 merge and passes three times out of three alone. It feeds a
framed message through `client.consume` in seven-byte slices and then does this:

    try? await Task.sleep(nanoseconds: 200_000_000)
    #expect(received.uri == "file:///a.swift")

A fixed sleep is not synchronisation. Note the failure is *silent about its cause*:
it reports `received.uri` as wrong, which reads as a framing bug in the thing under
test. Two people went looking at the wrong code because of it.

**`PerformanceTests.foldComputationIsReasonableOnHugeFile`** (backlog 0480) expects
fold computation over 100k lines under 10 seconds of **processor** time. Measured,
all three conditions:

| condition | processor time | verdict |
|---|---|---|
| the test on its own, six runs | 5.81, 5.83, 5.83, 6.02, 6.97, 7.15 s | green, margin 1.4–1.7× |
| inside `make test`, nothing else running | 10.10 s | **red**, by 1 per cent |
| inside `make test`, fourteen spinners | 10.44, 10.78, 11.09 s | **red**, by 4–11 per cent |

So it is neither a slow fold nor a busy machine: a full `make test` on an idle
machine is already enough to make it red about half the time.

This is the failure 0472 already fixed once in the same file, and processor time was
the fix. **That was right and it is not enough.** `cpuTime` is not
concurrency-independent — the same arithmetic costs more cycles when thirty-odd
threads compete for cache and memory bandwidth, and this measurement is 1.7× larger
inside the suite than outside it. `cpuTime` removed the scheduling and left the
contention.

From `.abydos/backlog/open/0530-…` and `.abydos/backlog/open/0480-…`, merged here
because they are one fault with two faces: a number guessed in a condition nothing is
ever measured in.

## What Changes

- `readsAMessageArrivingInPieces` waits for the message rather than sleeping, so the
  assertion cannot run early and the test takes microseconds instead of 200ms.
- Where a dozen tests want "wait until this closure has been called once, or fail",
  that lives in one place, with a timeout used as a **failure bound** rather than as
  the expected wait. That is not the same bet as a sleep.
- The three bounds in `PerformanceTests` are re-decided with the suite running,
  because "on its own" is the condition none of them is ever measured in. The numbers
  above are written beside whatever is chosen, so the next person does not re-measure
  all three conditions.
- `Task.sleep` appears **45 times** across the AbydosKit tests, in a dozen files.
  Which of them are in scope is decided and written down — the in-process ones are
  the cheap and certain wins; a live test waiting on a container may genuinely have
  nothing to await, and pretending otherwise trades a flake for a hang.

## Capabilities

### New Capabilities
- `test-timing`: how a test waits and how a performance bound is set — that a test
  synchronises on the thing it is about rather than on the clock, and that a timing
  budget is stated in the condition it is measured in.

### Modified Capabilities
<!-- None. -->

## Impact

- `Tests/AbydosKitTests/LSPFramingTests.swift`, and the other 44 `Task.sleep` sites
  in a dozen files, of which only some are in scope.
- `PerformanceTests` — all three bounds, not just the fold one, since they were set
  by the same reasoning.
- Any shared wait helper, which is new.
- Not in scope: raising the 200ms or widening a bound and calling it done. That
  trades a red run for a slow suite and keeps the bet.
