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
every load: `PlantUMLServerTests` draws the same diagram through a pipe and
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
`DrawioLiveTests` (1.0 → 0.1 s), `PlantUMLServerTests` (0.5 s, with its ratio kept
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

## Estimate

2026-08-11 19:33 — about three hours left

## Steps

- [x] Say what the claim is in numbers — warm against a container, not against 0.5
- [x] Choose: a ratio, a budget with room, or out of the suite behind `SCALE=1`
- [x] `make timing`, and `Stopwatch` beside `MachineLoad` to carry the argument
- [ ] Do the same for `PseudoTerminalTests`, whose timeout has the same shape
- [x] Look for others: any assertion on wall-clock in a suite that runs parallel
- [ ] Prove it — the suite green ten times over, and once under a deliberate load
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if anything does
