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

## The refusal, and what it turned out to be

The refusal was read, and it said the same sentence four runs running:

> the first render gave up after 180.3s: the server never answered in 180.1 s of
> a 180.0 s start deadline, over 789 attempts; last: Could not connect to the
> server. — load 13.7 over 10 cores (1.4 per core)

`neverAnswered`, then. The container started, the port was published, and eight
hundred connections to it were refused over three minutes. Not a slow JVM: a
*missing* one.

**It is not the machine and it is not the whole suite.** Two suites are enough,
and with those two it fails every time:

    xcrun swift test --filter PlantUMLServerLiveTests --filter DiagramExportLiveTests

Four runs, four failures, at 0.5 to 1.4 runnable per core — a quieter machine
than any run in this entry above. Alone, the same test passes in 1.4 seconds at
2.5 per core. So the reproduction is now one command that takes three minutes
instead of a full suite that fails sometimes, which is most of what was missing.

**The cause, from docker's own event log rather than from the test.** Running
`docker events` beside the pair prints this, all inside one second:

    create abydos-plantuml-server-47041-2     ← PlantUMLServerLiveTests' server
    start  abydos-plantuml-server-47041-2
    create abydos-plantuml-server-47041-3     ← DiagramExportLiveTests' server
    start  abydos-plantuml-server-47041-3
    kill   abydos-plantuml-server-47041-2     ← one `docker rm -f` with both
    kill   abydos-plantuml-server-47041-3        names on it
    die/destroy both

`DiagramExportLiveTests` tidies up after itself with

    ToolContainers.shared.release(withPrefixes: ["abydos-plantuml-server-", …])

and `release(withPrefixes:)` chooses by *role prefix and process id*. In the app
a role has one owner, so that is the same set as "mine". In a test bundle it is
not: two suites run at once in one process, both start a container playing the
role `plantuml-server`, and both names carry the same pid. So the export test's
cleanup removed the other suite's server — the one it was in the middle of
waiting for. Its own comment says "By name, and only the names this test's
renders make", and that sentence was simply not true of the call underneath it.

`PlantUMLServerLiveTests` has the same scan written out by hand in its
`removeAll`, so it does this to the export test in the other direction too.

**Why the failure costs three minutes.** `fetch` treats "cannot connect to host"
as *still starting* and retries until `patience`. That is right for a JVM that
has not finished coming up and wrong for a container that has been destroyed,
and there is no telling the two apart from a refused connection. So a server
removed a second after it started is asked eight hundred times and then reported
as never having answered. **That is the whole of the 193 seconds this entry
called the finding**: 180 of patience spent on a port that had already gone, plus
the pipe render and the runtime's own overhead. The number was real and the
reading of it — "the extra time is the new patience being spent and the render
giving up anyway" — was exactly right. What it did not say, and could not, is
that the thing being waited for had been deleted.

**And it explains the second shape.** When the export test's cleanup lands after
the first render has succeeded rather than during it, the warm render finds its
server gone, forgets it, and starts another — seconds, not hundredths. That is
`warmSeconds < 0.5` failing at `PlantUMLServerTests.swift:247`. One cause, two
faces, depending on which second the neighbour finishes in.

## Steps

- [x] Run until it fails and read the refusal, which now names which of the
      four things happened
- [x] Find what makes it happen, and reproduce it on demand rather than by
      waiting for a full suite
- [x] Prove the cause from the runtime's own event log, not from the test's
      account of itself
- [ ] Stop it: whatever it is, in the place it happens
- [ ] A test that fails on the old code and passes on the new one
- [ ] The second shape of this failure — the timing assertions rather than the
      refusal — says which thing happened, the way the refusal now does
- [ ] Full runs, repeatedly, with the load average written beside each
- [ ] Write down here what was ruled out on the way
- [ ] The spec, if the behaviour changed
