# 472. A timing test whose budget measures the test harness

`MermaidLiveTests.drawingIsFastEnoughToDoWhileSomebodyTypes` asserts `each < 0.5`
on a warm render. It went red **three times in one day** and each time it was
called environmental, correctly, and each time somebody had to stop and prove
that. Measured today, same commit, same machine:

    alone                        0.0139 s   load 16.9
    in the suite, passing        0.4619 s   load 37.3
    in the suite, failing        0.5041 s   load 37.3
    in the suite, failing        0.6050 s   load 35.0

**The suite's own parallelism is what puts the machine at load 37.** So the number
being asserted on is not the renderer's speed, it is the renderer's speed while
three hundred and fifty other suites run — and 0.46 against a 0.5 budget is not a
margin, it is a coin. Three agents building alongside made it worse, but the
passing run had none: the suite alone gets within eight per cent of failing.

The test already prints its own load, which is why every one of today's diagnoses
was quick rather than long. That instinct was right and the assertion is what
needs to catch up with it.

## The thing it is really protecting

The comment underneath says it: the decision this rests on is that a *warm* render
costs hundredths of a second where a container with no server mode to keep warm
costs about a second each. That is a **fortyfold** difference and it is the claim
worth defending. A budget of 0.5 s does not defend it — it sits between the two
answers and is closer to the wrong one. 0.0139 against 1.0 is the measurement; the
test is asserting on neither.

## Worth deciding

- **A ratio rather than a wall-clock**, which is what the claim actually is. Time
  a cold render and a warm one in the same run and assert the warm one is far
  cheaper; a loaded machine slows both and the ratio holds.
- **Or a budget with room in it.** If it stays absolute it wants to be far enough
  above the real figure to mean something — an order of magnitude below the
  container it is arguing against, rather than a hair under the number the suite
  itself produces.
- **Or take the timing out of the suite** and leave the correctness there, with
  the number behind `SCALE=1` like 0453's corpus rename. That keeps the claim
  measurable without making `make test` a lottery.
- **How many others are like this.** This is the one that fired today;
  `PseudoTerminalTests.runsACommandAndCapturesOutput` also timed out twice — 124 s
  waiting for output that takes 0.35 s, at load 54 and 65. That one is a timeout
  rather than a budget, but it has the same shape and should be looked at in the
  same pass.

Whatever is chosen, **the load line stays.** It is the reason these were diagnosed
in minutes instead of being chased as regressions.

## The claim, in the numbers it is actually about

Measured on this machine, ten cores, same commit:

| | warm render | load | per core |
|---|---|---|---|
| Mermaid, alone (`make timing`) | **0.0118 s** | 5.8 | 0.6 |
| Mermaid, inside `make test` | **0.5975 s** | 40.6 | 4.1 |
| draw.io, alone (`make timing`) | **0.0054 s** | 5.8 | 0.6 |
| draw.io, inside `make test` | **0.1587 s** | 34.6 | 3.5 |
| a container with no server mode | **≈1.0 s** | — | — |

So the claim is **0.0118 s against 1.0 s: a factor of eighty-five**, and the old
bound of 0.5 s was not between them so much as sitting on top of what the suite
itself produces. And the arithmetic that decides the whole item: **the harness
costs a factor of fifty** (0.0118 → 0.5975) **where the effect it is meant to
detect is a factor of eighty-five.** Those are the same order. No absolute bound
measured inside `make test` can tell the two apart.

One more reading, which explains why this passed all morning and failed all
evening rather than failing every time. The passing run printed:

    MERMAID: 0.5975s a warm render, load 40.6 over 10 cores (4.1 per core)
    MERMAID: not timing the warm render — load 40.6 over 10 cores (4.1 per core)

`MachineLoad.canBeTimed` is `perCore < 4.0`. It **passed by being skipped, at
4.1**, with a figure that would have failed by 20 per cent. The suite's own
parallelism puts this machine at 3.5–4.1 per core, which is exactly where that
threshold sits — so the guard and the failure were being decided by the same coin.
The suite growing from 2410 to 2450 tests did not move the number over the bound;
it moved the load over the *guard*, and let the bound through.

## Decided: out of the suite, and then a bound with real room in it

Both, and in that order, because the second is only possible once the first is
done. `make timing` — `TIMING=1`, `--no-parallel`, the three suites that time a
warm render — asserts the bound. `make test` takes the measurement, prints it with
the load, and asserts nothing about the clock. `Stopwatch` in
`Tests/AbydosKitTests/MachineLoad.swift` is the gate and carries the argument.

The bound could then be made honest: **0.1 s**, an order of magnitude below the
container it argues against and eight times over the figure it measures. It was
0.5 s, which is neither.

### Why a ratio lost

It was the option this item leaned towards, and it fails on what the claim *is*.
"Fast enough to do while somebody types" is a statement about a person, and a
person's tolerance is an absolute quantity — a ratio cannot express it. A cold
render against a warm one would pass with a warm render of two seconds, provided
the cold one took twenty. It would assert that the page stays loaded, which is
true and is not the claim.

It is also not measurable here. `MermaidRenderer.shared` is a singleton with no
way to unload its page, and eight tests in the same suite have already warmed it
before this one runs — there is no cold render left to take. And the thing the
claim compares against is a *container*, which this test does not start.

Where a same-run ratio genuinely is available it is now the assertion that runs at
every load: `PlantUMLServerLiveTests` draws the same diagram through a pipe and
through the server seconds apart in one run, and `warmSeconds < oldSeconds / 4` is
kept unconditional while `warmSeconds < 0.5` moved behind `make timing`. That is
this option winning where it applies.

### Why a budget with room lost, on its own

Arithmetic, above: an order of magnitude below 1.0 s is 0.1 s, and `make test`
produces 0.5975 s for Mermaid and 0.1587 s for draw.io. A bound with real room in
it is red on every run of the suite. A bound the suite can pass is above the
container it argues against and therefore asserts nothing. It only becomes
available *after* the timing leaves the suite — which is why the answer is the
third option with the second one on top of it, rather than the second one alone.

## `PseudoTerminalTests` is not the same shape. It is a real bug — now 0476

This item expected a fourth timing assertion here and there is no timing assertion
here at all. The sweep confirms it: `runsACommandAndCapturesOutput` asserts
`#expect(sawOutput)` and nothing about a duration. The 120 s is `Patience.seconds`,
a hang detector, and **it was detecting a real hang.**

A child that writes its line and exits before anything has read the pty master
**loses the output outright.** Not late — gone. So the wait was not waiting for a
slow `/bin/echo`, it was waiting for something that no longer existed, and no value
of the timeout helps.

Reproduced five runs out of five, under `make test` with fourteen spinners beside it
at 9–26 runnable threads per core, with the original symptom appearing verbatim
twice: `expected output after 120.0s, got: ""`. Reproduced again standalone with no
dispatch anywhere near it, which is what says it is not about which queue got a
thread. And the discriminating measurement, which is the one worth keeping:
`ABYDOS_TERM_LOG` records on the *reading* queue, before the hop to the callback
queue, and on the runs where attempts 10 and 19 lost their output the log is missing
exactly `gone-9` and `gone-18` and holds every other word. The bytes were never
read — not read and undelivered.

**Filed as 0476 rather than fixed here, and that is a judgement worth stating.** Two
fixes were written and measured on this branch before that was clear — draining the
pty before closing it, and noticing the exit with `WNOWAIT` so the child is not
reaped — and **neither works**, both measured, both reverted. The remaining
candidate is the parent holding its own fd on the slave so the pty is not torn down
while output is still queued, and the first attempt at measuring *that* hung. A
change to the pty's lifecycle, in the file every terminal pane in this app runs
through, is not something to land on the strength of a diagnosis that has already
been wrong twice in one evening.

The test that catches it — twenty short commands rather than one, so it fires in one
test rather than one run in many — was written here, committed at `1c0c108`, and
then **taken back out.** It reddens `make test` under load, and this item exists to
stop the suite going red for reasons that are not the branch under test; adding one
would have been the item undoing itself. It belongs to 0476, with the fix.

What this branch keeps costs nothing and saves the next diagnosis: the failure
message now carries the load, the bytes it actually got, and the sentence "this is
0476 rather than a slow machine if it is empty". Three people read that red as
environmental. The fourth will not have to.

## The sweep: every wall-clock assertion in a suite that runs in parallel

The whole of `Tests/` uses three clocks and no others — `Date()` differencing,
`DispatchTime.uptimeNanoseconds`, and `clock_gettime(CLOCK_THREAD_CPUTIME_ID)`.
No `ContinuousClock`, no `CFAbsoluteTimeGetCurrent`, no `XCTest` `measure`. And
`.serialized` turns out to protect nothing here: it orders tests *within* a suite,
so a serialised suite still runs beside the other three hundred and fifty. Every
one of these is exposed.

**Absolute wall-clock bounds, and nothing guarding them** — worse than the one
this item was filed about, and in a suite that runs on every `make test`:

| where | was | now |
|---|---|---|
| `PerformanceTests.buildsLargeRopeQuickly` | `elapsed < 5.0` wall, read 648 ms at load 40 | processor time |
| `PerformanceTests.foldingStateMapsLinesQuickly` | `collapseTime < 2.0` wall, read 217 ms | processor time |
| `PerformanceTests.foldingStateMapsLinesQuickly` | `mapTime < 2.0` wall, read **843 ms** at load 34 | processor time |

The third is the one that was about to go. A margin of 2.4 on a number the suite's
own parallelism moves by a factor of thirty is the same coin as Mermaid's. And the
fix needed nothing invented: the same file already holds `cpuTime`, whose comment
records the identical lesson learned on `foldComputationIsReasonableOnHugeFile`
("failed in four full runs out of six while passing every time it was run alone").
These three were simply the ones that conversion missed. Nothing in this file waits
for anything, so processor time is the honest instrument — no gate needed, and the
bounds are unchanged and now mean what they say.

`Self.time` is kept for the two claims that are *ratios* between figures taken
seconds apart in one run — `lineLookupsAreLogarithmic`, `editsAreIndependentOf`
`FileSize` — and it now prints `MachineLoad.said` beside every figure, so a number
copied out of a log later carries the one fact needed to argue with it.

**Guarded absolutes, now behind `make timing`:** `MermaidLiveTests` (0.5 → 0.1 s),
`DrawioLiveTests` (1.0 → 0.1 s), `PlantUMLServerLiveTests` (0.5 s, with its ratio kept
unconditional).

**`TerminalThroughputTests`** asserts nothing at all — five tests, every body
ending in a `print`, and the suite off unless `ABYDOS_BENCH` is set. It is already
the answer this item is about, arrived at independently, and its own doc comment
gives 0472's reason for the gate: "they saturate a core for as long as they run,
which is enough to make the timing-sensitive tests elsewhere fail". The one gap was
that it was the only timing file in the tree printing a rate with **no load beside
it** — and 0474, which is what those numbers were written for, had to say in the
item that its table was taken at load 25.9 and that the absolutes should not be
quoted anywhere. Fixed: every `BENCH` line now carries the load.

`ScaleLiveTests` is the same answer again and is the precedent `make timing`
follows — `SCALE=1`, `--no-parallel`, and a doc comment that says outright
"nothing here asserts a duration".

### Wall-clock bounds looked at and deliberately left alone

These compare a duration, so the sweep found them, but each has so much room that
load cannot reach it. They are what "a budget with real room in it" looks like when
it is available, and changing them would be churn:

- `LSPTests.aServerThatIsNotReadingDoesNotHoldUpTheSender` — `< 5` seconds on a
  call that costs microseconds and took the whole thirty before the fix. Six orders
  of magnitude of room.
- `LSPTests.aRequestAgainstASilentServerGivesUpOnTime` — `< 30` against a server
  told to `sleep 120`.
- `ToolProcessTests` — `waited < 60` against the same `sleep 120`; the comment
  records a 10 s spelling failing at 12.3 s, so this one has already been widened
  once for exactly this reason.
- `ToolInventoryLiveTests` — a container's start time within `120` s of now.
- `LaunchClockTests` — process start within a day.
- The **lower** bounds, which load cannot break in the direction that matters:
  `StreamedOutputTests` (pieces ≥ 1.5 s apart, so output is streamed and not one
  lump), `ContainerImageTests`, `StallWatchTests`.
- The **CPU-time** bounds in `PerformanceTests` (viewport highlight `< 0.05`,
  keystroke `< 0.002`, reparse, fold ranges `< 10.0`). Load-immune already; that is
  the point of them.

## Ruled out on the way

- **Widening the Mermaid budget.** The first thing anybody reaches for, and it
  cannot work: see the arithmetic above. Any bound the suite can pass is above the
  container the test argues against.
- **Lowering `MachineLoad.busy` from 4.0 so the guard catches the suite.** This
  would have made the symptom go away and is the worst available answer. The guard
  would then skip on nearly every `make test`, so the bound would be dead code that
  looks alive — and 0435's argument for having the guard at all is that it should
  be *rare*, not routine. The threshold is unchanged. What changed is that the
  bound is no longer asked of a run that cannot answer it.
- **A cold-against-warm ratio for Mermaid or draw.io.** Ruled out twice over: the
  claim is absolute (see above), and there is no cold render available — the
  renderer is a shared singleton, already warm by the time this test runs, with no
  way to unload its page. Kept where it does work, in `PlantUMLServerLiveTests`.
- **`SCALE=1` itself, rather than a verb of its own.** `SCALE=1` means "the corpus
  is on this disk and I want it walked", and `ScaleLiveTests` needs several
  gigabytes of Eclipse beside the checkout. A warm render needs nothing. Sharing
  the variable would have made `make scale` fail for want of a corpus on anybody
  who only wanted a render timed. `TIMING=1` and `make timing` instead — the shape
  of `SCALE=1`, not the same switch.
- **Draining the pty before closing it, and `WNOWAIT`.** Both written, both
  measured, both wrong. See the 0476 section.
- **Raising or lowering `Patience.seconds`.** No value helps a wait for something
  that has been discarded. Unchanged.
- **`.serialized` as protection.** It orders tests *within* a suite. A serialised
  suite still runs beside the other three hundred and fifty, so it protects nothing
  that this item is about — worth writing down, because it reads as though it
  should.

## Proof

**Thirteen runs of the full suite, 2450 tests in 355 suites. Twelve fully green.**
The thirteenth failed on one thing, `ContainerLSPLiveTests`'s jdtls case, which is
0473 — two containers were still running whose owning pids were long dead
(`abydos-lsp-jdtls-32768-25` and `-44368-25`, started at 19:22 and 19:24). Removed,
re-ran, green. **Nothing timing-related failed in any of the thirteen.**

Ten consecutive, on a machine that was busy with other people's work throughout —
2.4 to 9.9 runnable threads per core, which already spans and exceeds the 5.4–6.5
of the reds this item was filed about:

    per core  3.5  3.9  4.1  5.6  6.0  6.7  6.8  7.3  8.2  8.6  9.9

Then two under fourteen deliberate spinners, at **15.8 and 22.6 per core**, and one
more at 14.2 after the sweep.

**The warm render the old bound was asserting on, across those thirteen runs:**

    0.1689  0.4466  0.4511  0.4743  0.4847  0.5309  0.5484  0.5591
    0.5782  0.5910  0.6828  1.0684  1.1024

A factor of six and a half, from the same code on the same machine, decided
entirely by what else was running. **Eight of the first eleven are over the old
0.5 s bound**, and the last two are over **1.0 s** — that is, at 15.8 and 22.6 per
core a warm render costs *more than the container it is arguing against*. There is
no absolute number that survives that range, which is the item's thesis arriving as
a measurement rather than as arithmetic.

Every one of the thirteen printed the figure and the load, and the line saying the
bound was not applied. That is the part to keep.

### What is not proven here

`PlantUMLServerLiveTests` — whose ratio this item made unconditional and whose
absolute it moved behind `make timing` — **never ran**. It needs a container runtime
and skipped itself on every one of the thirteen. It compiles, and the change is two
lines with no new variables in them, but it is the one thing here covered by
argument rather than by a green, and somebody with a runtime up should watch it once.

`make timing` itself was run on a quiet machine and took the asserting branch — the
proof being that it printed the measurement with **no** "not bounding" line, where
`make test` prints both. So the bound is live rather than vacuous, which is the trap
the old code fell into: it was passing *by being skipped* at 4.1 per core.

## Steps

- [x] Say what the claim is in numbers — warm against a container, not against 0.5
- [x] Choose: a ratio, a budget with room, or out of the suite behind `SCALE=1`
- [x] `make timing`, and `Stopwatch` beside `MachineLoad` to carry the argument
- [x] Do the same for `PseudoTerminalTests`, whose timeout has the same shape
      — it does not have the same shape. It is a defect, reproduced, and filed as
      0476; the timeout is a hang detector and is left exactly as it was.
- [x] Look for others: any assertion on wall-clock in a suite that runs parallel
- [x] Three wall-clock bounds in `PerformanceTests` onto processor time
- [x] Every printed duration and rate carries its load, `BENCH` lines included
- [x] `make warnings` at zero for this repository's Swift
- [x] Write down here what was ruled out on the way
- [x] Prove it — the suite green ten times over, and once under a deliberate load
- [ ] No spec delta — nothing the program does changed

The last one will not be ticked, because there is nothing to tick. Everything here
is the test suite and two `make` verbs; `spec/` is the account of what the *program*
does, and a requirement about how this repository measures itself does not belong in
it. The one line of `Sources/` that changed is `var` to `let`.
