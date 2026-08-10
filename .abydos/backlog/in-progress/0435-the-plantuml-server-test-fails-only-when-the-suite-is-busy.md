# 435. The PlantUML server test fails only when the rest of the suite is running

`PlantUMLServerLiveTests.theSecondDiagramIsTheSamePictureAndArrivesAtOnce` fails
in a full `make test` and passes on its own, which makes every merge gated on the
suite a coin toss.

**Measured, on this machine, today.**

| how it was run | result | wall clock for that test |
|---|---|---|
| `make test` (1905 tests) | failed | 85.99 s |
| `make test` again | failed, and the run before it reported three issues rather than one | — |
| `make test FILTER=PlantUMLServerLiveTests` | passed | 1.87 s, whole suite 4.28 s |

Forty-six times slower in company than alone, and the number of issues varies
between runs of the same code, which is what says load rather than logic.

**Where it fails.** `PlantUMLServerTests.swift:189` — `let warm = try #require(first)`.
So it is *not* the timing assertion the test is named for. The first warm render
came back **nil**: the server never answered at all, and the comparison the test
exists to make was never reached.

**Not the draw.io work it surfaced beside.** Confirmed twice over: the agent that
merged 0426 stashed its branch and ran the full suite twice on clean `main`, one
green and one failing this same test; and it passes here in isolation on `main`
with 0426 merged.

## The likely mechanism, not yet proved

`PlantUMLServers` gives a server 60 seconds to start (`startDeadline`) and 20 to
answer (`requestTimeout`). Starting one is a `docker run` plus a JVM, which is
about two seconds idle — the item that built this measured 2.0 s down to 0.05 s,
which is the whole reason the warm server exists. Under a full suite, with
several other live tests each holding containers of their own and whatever else
the machine is doing, that start is competing for the same cores and the same
docker daemon. If it crosses 60 seconds the render answers nil and the test
requires a value that is not there.

What would confirm it: the reason the render gave up. The test asserts on the
absence and so throws away everything about *why*, which is the first thing to
fix whatever the cause turns out to be — a nil here reads as "the feature is
broken" when it may mean "this machine was busy".

## Which way to fix it is a judgement

Both are defensible and they say different things:

- **The test waits properly.** A live test whose subject is a container has no
  business inheriting the app's user-facing deadline; the app's 60 seconds is a
  promise to somebody watching a preview, not a statement about a build machine.
  Giving the test its own, longer patience keeps it honest about *correctness*
  and stops it reporting on load.
- **The deadline is genuinely too tight.** If a laptop doing two things at once
  can miss 60 seconds, then a user on a busy machine sees the preview fail too,
  and the test is right to notice. That makes this a real defect rather than a
  flaky test, and the answer is in `PlantUMLServer`, not in the test.

Establishing which needs the failure reason above. Until then, guessing at the
number would be moving a threshold until the red went away, which is how a real
fault gets buried.

## Why it is worth doing rather than tolerating

It has already cost time in two sessions: once for the agent that hit it while
finishing 0426 and had to prove it was not theirs, and once here. A suite that
fails for reasons unrelated to the change under it teaches everybody to read
"failed" as "probably fine", and that is the property worth protecting — it is
the only thing standing between a merge and `main`.

## Merged, and not settled — three runs on a quiet machine

The work landed unfinished: the agent doing it was stopped by an account spend
limit partway through the sentence "now the verification runs, full suite,
repeatedly, under load". What it built is good and is in — the refusal that says
*which* failure happened, one place saying how patient a live test is, and a real
process leak it found among the noise. What it did not get to do is prove the red
is gone, and on the evidence it is not.

Three full runs on **a quiet machine**, load average 6 to 13 rather than the 27 to
386 every earlier observation was taken at:

| run | result | wall clock |
|---|---|---|
| 1 | **failed**, `aServerRemovedBehindItsBackStillDrawsTheDiagram` | **193 s** |
| 2 | passed, 2011 tests | 72 s |
| 3 | passed, 2011 tests | 72 s |

**The 193 seconds is the finding, not the failure.** A normal run is 72. The extra
two minutes is the new patience being spent and the render giving up anyway — so
the deadline was not what was wrong, and raising it bought a longer wait before
the same red. That is precisely the outcome this entry warned against when it said
not to move a threshold until the red goes away.

It also moves the question. Every earlier observation was under heavy load, which
made "the machine was busy" a sufficient explanation. This one was not: at a load
average of 7, on ten cores, with the same test passing alone in 1.4 seconds. So
whatever this is, it is something the *rest of the suite* does to this test rather
than something the machine does to it — contention for the container runtime, or
another suite removing a container this one is using, which the file's own note
already records as having happened before ("two of these running at once were
removing each other's servers mid-render").

Next step, and it is now a much narrower question than the entry opened with: run
the suite until it fails and read the refusal, which now says which of the four
things went wrong. One failing run with that sentence in it should end this.

## Steps

- [ ] Run until it fails and read the refusal, which now names which of the
      four things happened
- [ ] Find what makes it happen, and reproduce it on demand rather than by
      waiting for a full suite
- [ ] Prove the cause from the runtime's own event log, not from the test's
      account of itself
- [ ] Stop it: whatever it is, in the place it happens
- [ ] A test that fails on the old code and passes on the new one
- [ ] The second shape of this failure — the timing assertions rather than the
      refusal — says which thing happened, the way the refusal now does
- [ ] Full runs, repeatedly, with the load average written beside each
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if the behaviour changed
