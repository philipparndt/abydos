## Context

`MachineLoad.swift` holds the suite's answers to timing: `Patience.seconds` for
how long a wait may take, `Stopwatch.maySay` for whether a performance bound may
be asserted at all, and `Stopwatch.mayClassify` for the narrower case of using a
duration to tell two mechanisms apart. `test-timing` states the rules those
serve.

`mayClassify` was written for exactly the two tests this change alters, and its
documentation records them going red at 27 runnable threads per core with both
deadlines working. It also records why its guard is not enough: the load average
is a one-minute decayed figure, so it lags, and "a red caused by that burst still
lands".

## Goals / Non-Goals

**Goals:**

- The three tests assert what they are about, at any load.
- The durations stay visible, with the load beside them.

**Non-Goals:**

- Removing `mayClassify`. It remains right for a duration that genuinely is the
  only way to tell two mechanisms apart — this change is that there were none
  such among these three.
- Changing any deadline in the app. A one-second deadline firing at 41.7 s
  under a suite is the machine, and the app's own numbers are for a person at a
  screen.

## Decisions

**Name the mechanism, do not time it.** An error case and a message are exact
at any load; a midpoint between two durations is a guess about the machine
dressed as a claim about the code. Both tests already had the exact assertion
sitting beside the fragile one — `#expect(throws:)` needed only to be told
*which* error, and `reason.contains("did not answer")` was already there.

**A test's patience is not a person's.** The app's ten seconds for signature
help is a UI decision and stays. What was wrong was a test inheriting it: the
question under test is what the server says about the parameter, and how long
sourcekit-lsp takes to say it while 4023 tests run is the machine's business.

*Ruled out: raising the midpoints.* Sixty seconds was already sixty times the
deadline and it was exceeded. The next number would be a guess with the same
shape, and the run would go red again on a busier day — which is the loop 0435
describes.

*Ruled out: `withKnownIssue` on the flaky pair.* That marks a test as expected
to fail, which is a lie about working code and would have hidden the two
measurements this change turned out to be about.

## Risks / Trade-offs

**A deadline that stops firing at all** → The throw and the message still catch
it: a wait that never ends fails the test by never returning, and the run's own
timeout ends it. What is lost is noticing a deadline that fires *late*, and
that was never reliably caught either — the bound was breaking on load, not on
lateness.
