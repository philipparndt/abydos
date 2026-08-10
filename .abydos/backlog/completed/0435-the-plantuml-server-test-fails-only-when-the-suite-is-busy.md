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
- [x] Stop it: whatever it is, in the place it happens
- [x] A test that fails on the old code and passes on the new one
- [x] The second shape of this failure — the timing assertions rather than the
      refusal — says which thing happened, the way the refusal now does
- [x] Full runs, repeatedly, with the load average written beside each
- [x] Write down here what was ruled out on the way
- [ ] The spec, if the behaviour changed

      Nothing shipped changed, so there is no delta. The only production edit is
      the deletion of a method nothing in `Sources/` called; the app's previews,
      its deadlines and its fallback are untouched. `spec/` holds no capability
      file this would land in either.

## What was run, and what a green run is worth here

**The reproduction, which is the part that means something.** Two suites is
enough, so the evidence is a three-minute command rather than a full suite run
until it happens to go wrong:

    xcrun swift test --filter PlantUMLServerLiveTests --filter DiagramExportLiveTests

| | runs | result | wall clock | load, per core |
|---|---|---|---|---|
| before | 4 | **failed, 4 of 4** | 181–183 s | 0.5 – 1.4 |
| after | 5 | passed, 5 of 5 | 2.7–3.0 s | 1.7 – 2.7 |

Note which way round the load is. Every failure was on a quieter machine than
every pass.

**Eight full `make test` runs on the finished code, all green**, 2109 tests each:

| run | load at the start | load per core when PlantUML drew | warm render |
|---|---|---|---|
| 1 | 9.4 | 1.9 | 0.026 s |
| 2 | 13.7 | 6.3 — too busy to time, and it said so | 0.044 s |
| 3 | 44.1 | 5.7 — the same | 0.049 s |
| 4 | 29.5 | 3.4 | 0.048 s |
| 5 | 18.5 | 3.1 | 0.040 s |
| 6 | 14.9 | 2.7 | 0.035 s |
| 7 | 13.6 | 2.3 | 0.049 s |
| 8 | 15.2 | 3.2 | 0.092 s |

The machine was not quiet for any of them — another agent was building in a
worktree beside this one the whole time, which is why the figures run from 9 to
44. That is the right condition to have tested under and it is worth saying that
it was luck rather than design.

Three further full runs were made on an intermediate state and are not in the
table. All three failed, and only on the new lint going red against its own
comment; one of them also caught the pty test below.

**What a green run is worth here, said plainly.** Less than usual, and this
entry has already been wrong once about exactly that. Eight passes is not proof:
the failure needs the export test to finish inside the other test's start, and
anything that moves the two apart hides it without fixing it. What carries the
weight is not the eight — it is that the mechanism was read off docker's own
event log, that both names appear on one `rm -f`, that the code which produced
that command is gone rather than tuned, and that the two-suite reproduction went
from four failures out of four to five passes out of five across the change. The
eight full runs are a check that nothing else broke, and that is all they are.

**Still not proved:** that this was the *only* cause. Every sighting in this
entry is consistent with it, and the two shapes it produces are the two shapes
that were seen — but every sighting before today was under load heavy enough to
be its own explanation, and those runs cannot be gone back to and read.

## What it came to

A role is not an owner, and that sentence is the whole fix.

`ToolContainers.release(withPrefixes:)` is **gone**. It was written when
`removeAll` took a devcontainer out from under the suite beside it, and it
narrowed the set from "every container this process registered" to "every
container playing my role". That is one step short, and the step it is short of
is this item: in the app a role does have one owner, but in the test bundle two
suites both keep an `abydos-plantuml-server-…` and both names carry the one
process's pid, so "mine" and "everyone playing my part" were the same set in the
only place the method was ever called from. Nothing in `Sources/` called it at
all. There is no set-of-mine that can be computed from a name, so nothing
replaces it.

What replaces it at each call site is the names that site already knew:

- **`DiagramExportLiveTests`** lets `PlantUMLServers.stopAll` name its own — the
  actor removes the servers it is holding, which is exactly the set it started.
  That needed the cleanup moved out of a `defer`, since a defer body may not
  await; the failure is carried past the cleanup in a `Result` and rethrown
  after. The per-render export containers need nothing: they are `docker run
  --rm` and `DiagramExport` releases each as it finishes with it.
- **`PlantUMLServerLiveTests`** drops the register scan it had written out by
  hand. It never found one of this suite's own — they are all noted as they are
  started — and the only thing it ever did find was the export test's server,
  which it then removed mid-render. The safety net caught nothing but the
  neighbour.
- **`ContainerCleanupTests`** now forbids both calls in `Tests/` rather than
  forbidding one and recommending the other, and says what to do instead. It is
  a lint and not a proof, and it went red the first time it ran because the
  comment explaining it spelled out the name it forbids — which is the property
  working.

**The timing assertions stay, and this item is the argument for keeping them.**
The honest answer to "should a live test assert on timing at all" turned out to
be yes, here, because the one time `warmSeconds < 0.5` went red it was telling
the truth: the server really had been taken away and the warm render really did
take seconds. Deleting it would have removed the only thing in the suite that
noticed, and left a test named "arrives at once" asserting only that two renders
agree — which they would with no kept server at all. What was wrong was not that
it measured, but that a removed container and a slow machine arrived at the same
line looking identical. So the test now checks, before the stopwatch and at any
load, that the warm render came from the *same container*, and says so when it
did not:

> the warm render came from a different server: […] before, […] after. Something
> removed the container between the two renders, so the 2.104s this took is a
> container starting rather than a diagram being drawn — load …

That is what 0435's `Refusal` did for the render that gives up, done for the
failure that is not a refusal. Both shapes now name the cause instead of leaving
somebody to infer it from a number, and no threshold moved.

**Nothing shipped changed.** `startDeadline` is still sixty, `patience` is still
`Patience.forAContainer` for a live test, and the app draws previews exactly as
it did. The only production change is the removal of a method with no production
caller.

## Ruled out

- **The deadline.** Not it, and the entry above had already worked that out from
  the 193 seconds. Confirmed from the other end: the failing render's refusal
  says `neverAnswered` over 789 attempts, and the fix moved no deadline at all.
- **Load.** Not it. The reproduction fails four times out of four at 0.5 to 1.4
  runnable per core, quieter than any observation in this entry, and passes five
  times out of five afterwards at 1.7 to 2.7 — *higher* load, green. Load made
  the failure likelier by widening the window between the two suites, which is
  why every early sighting was under load and why that was so convincing.
- **Contention for the docker daemon**, which this entry offered as the other
  candidate. Not it: the daemon answered every command in the failing runs, the
  container started in under a second, and the port was published. Nothing was
  slow. Something was deleted.
- **The draw.io work beside it (0426)**, already ruled out twice above and not
  revisited.
- **Anything in `PlantUMLServer.swift`.** The actor behaved correctly throughout:
  it started a server, was told nothing when the server was destroyed, retried a
  refused connection as though the JVM were still coming up — which is the right
  reading of a refused connection when you have just started a container — and
  reported honestly that it never answered. There is no change to make here that
  would not be worse. Telling "the JVM is not up yet" from "the container is
  gone" would mean asking the runtime on every retry, which is a subprocess every
  200 ms for a minute, to improve a case that does not happen once the suite
  stops removing its own containers.
- **`MachineLoad.canBeTimed` being too generous or too mean.** Untouched. It was
  never what let this through: on the failing runs the load *was* low enough to
  time, correctly, and the number being timed was wrong for a reason that had
  nothing to do with the machine.

## What was seen and is not this

**`PseudoTerminalWriteTests.everythingWrittenArrivesEvenWhenItIsFarTooMuch`
failed once**, in one full run out of eight, on
`#expect(text.contains("line 2000 "))` — the middle of a 4000-line paste, with
the *end* having arrived. It passes eight times out of eight on its own. That is
the same shape of complaint this item opens with and a completely different
subject: a pty write under load, no container anywhere near it. Not diagnosed,
not touched, and worth an item of its own if it is seen again — writing it here
rather than filing it is only because a number minted in this worktree would
collide with the one being worked next door.

