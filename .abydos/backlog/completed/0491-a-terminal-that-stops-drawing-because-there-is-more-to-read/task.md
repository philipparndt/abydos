# 491. A terminal that stops drawing because there is more to read

Two performance fixes landed and were both reverted, because with either of them in the
terminal drew **one frame a second** while a program poured output. Neither was wrong
about what it made faster. The policy underneath them was wrong, and it had been wrong
all along — the fixes only made the machine fast enough to reach it.

    before both       renders=43   parse=505ms   build=250ms
    0488 in           renders=1    parse=690ms   build=2ms
    0488 out, 0489 in renders=1    parse=689ms   build=5ms

## The rule, and the question it asks

`RedrawThrottle.shouldDraw` is three lines and each is defensible:

    guard isBehind else { return true }
    guard behindFor >= burstHoldOff else { return false }
    return sinceLastDraw >= catchUpInterval

with `catchUpInterval` one second, `burstHoldOff` a quarter, and the call site passing

    isBehind: !pending.isEmpty

**That last line is the fault.** "There are bytes I have not parsed yet" is not the same
as "the picture I would draw is stale", and against an unbounded writer the queue is
*never* empty — firebench writes as fast as it is read, so the faster the drain, the more
reliably `isBehind` is true. Making the parser faster therefore made the screen stop.

The comment above it is right about the thing it was written for: a backlog is history,
and a screen replaying it frame by frame is an agent's clock sprinting through minutes it
already spent. That is a real fault and this must not reintroduce it. But it confused two
cases that look identical to `!pending.isEmpty` and are not:

- **Catching up after a pause** — a locked screen, an app switch, a scrolled-back pane.
  Thousands of frames are queued, all but the last are history, and drawing them in order
  is the fault the throttle exists for.
- **Keeping up with a live program** — output arriving as fast as it can be drawn, where
  every frame *is* current and the queue is non-empty only because more is already on its
  way.

## What was measured, so nobody re-derives it

- Parse went **up** with a faster parser — 505 → 689 ms — because a drain that keeps up
  reads more per second. Throughput improved; the time spent parsing per second rose.
- Before the speedups, the *reader was being suspended* at the backlog high-water mark.
  That suspension is what let `pending` empty, which is what let `isBehind` go false,
  which is what allowed forty-three frames a second. **The screen was being drawn as a
  side effect of the parser being too slow to keep up.**
- `build` is not implicated: 250 ms before, 2–5 ms after 0488, and `renders` was 1 in both.

## What a right answer probably looks like

Draw at the display's rate and bound the *parse* work per frame, rather than stop drawing
because there is more to read. The frame is already display-link driven; the drain
already has a `parseBudget` deadline and a backlog high-water mark. The pieces are there
and pointed the wrong way round.

Which means the question to answer first is **what "stale" means measurably**. Candidates,
none chosen: how far behind in *bytes*; how far behind in *time* (when did the oldest
unparsed chunk arrive); whether the queue is growing or shrinking. The last is the most
promising — a queue that shrinks is keeping up however deep it is, and a queue that grows
is the case the hold-off was written for.

**And whatever is chosen has to keep 0468's lesson**: a program that writes one frame and
exits must still have that frame drawn, and the pty discards unread output 600 ms after
the child exits.

## The two reverts this unblocks

- **0489** — the newline: log output's parse went from 698 ms of every second to 12, four
  and a half times on `plain`, and nothing has suggested it is wrong. It goes back first.
- **0488** — the row cache: 47× fewer cells on a screen that changes in part, nothing
  either way on the fire. Its branch also has an unexplained symptom against it, stale
  text when the shell rewrites the prompt line under cursor-up, which no bench covers.

## What every measurement here must report

`renders`. 0488 reported `ns/cell` for the fire and a collapse from forty-three frames a
second to one did not appear in its own table. `ABYDOS_METAL_PROBE=1` prints `renders`,
`cells/render`, `parse` and `build` together, and any change to this policy is a claim
about the first of those.

## First, the thing that makes half of the above wrong

**The three rows this item was filed on were not measured on the same terminal
engine.** `Settings.terminalGhosttyEngine` decides whether a pane is emulated by
`TerminalEmulator` or by libghostty-vt, and the app on this machine had it on —
because a throwaway defaults domain is *not* clean: `AppDelegate` calls
`Settings.migrate(from: "de.rnd7.ideai")`, which copies the whole of the user's
old domain into whatever bundle identifier a test build is given, unless
`appearance`, `terminalScheme` and `uiScale` are already set in it.

One binary — main with both reverts in — same window, same 11,750 cells, a minute
apart, load 6–8 over ten cores:

| engine | renders | cells/render | parse | build | end to end |
|---|---|---|---|---|---|
| ours (`TerminalEmulator`) | **38–45** | 11,750 | 502–527 ms | 226–265 ms | 55.1 MB/s |
| libghostty-vt | **1** | 11,750 | 686–697 ms | 5–6 ms | 1.4 MB/s |

The second row *is* the item's `0488 in` and `0489 in` rows, to the millisecond —
`renders=1 cells/render=10810 parse=689ms build=5ms` in the revert message against
`renders=1 cells/render=11045 parse=689ms build=5ms` here, on a build containing
neither fix. **So the collapse from forty-three frames a second to one was the
engine setting, not either merge**, and `build 250 → 2ms` was not the row cache
either: 250 ms over 43 renders and 5 ms over 1 render are both 5.8 ms a frame.

Both fixes were reverted for a measurement artefact. That does not make the policy
right — it was wrong, and the numbers below say so — but the "before both / 0488
in / 0489 in" table at the top of this item should be read as "our engine /
libghostty-vt / libghostty-vt".

## What "stale" means now

**How many seconds out of date the picture is: how long ago the oldest byte nobody
has parsed yet was read off the pty.** Zero when everything that has arrived is on
the grid. `RedrawThrottle.shouldDraw` takes `staleBy:` instead of `isBehind:`, and
the picture is drawn at the display's rate whenever it is under a quarter of a
second behind.

Why the other two candidates lose:

- **Bytes behind** are only staleness after dividing by a parse rate, and that rate
  moves by ten times between patterns (23 MB/s on plain against 179 on colour,
  before 0489) and by four and a half between builds of the parser. A byte
  threshold therefore means a different number of seconds for every pattern and
  every release — which is exactly the coupling that caused this fault. Seconds do
  not move when the parser gets faster.
- **Growing or shrinking** — the candidate this item guessed was most promising —
  is measurably backwards, and the burst harness prints the proof. Across one
  40,000-frame backlog `stale=` reads 1,921,640 ms, then 1,585,285, 1,227,283,
  855,634, 469,285: **a burst's queue shrinks, monotonically, from its first frame
  to its last.** It is the case the hold-off exists for and it is on the
  "shrinking" side of that line. A program keeping up holds a queue that is flat
  or shrinking too, so the sign of the derivative puts both cases on the same side
  and separates neither — and it needs a window to average over while the decision
  has to be made every frame.

## And where the backlog actually was

Not in the queue anything was counting. `PseudoTerminal` hopped to the main queue
**once per read** — fifteen thousand times a second on log output — and each block
carried its own bytes, so *the queue of blocks was the backlog*: a third of a
second of output on `plain`, nearly three seconds on libghostty-vt, invisible to
`pendingBytes`, unreachable by back-pressure, and stamped with the wrong time
because the old code timed a delivery from when the main thread got round to it.

Three changes, and they are one change:

- The arrival time is taken **on the reading queue**, before the hop. The wait for
  the main thread is part of how far behind the screen is, and a stamp taken after
  it reports zero for exactly the backlog it is meant to find.
- Reads are **merged** while a hand-over is still waiting, so only ever one block
  is queued and the unparsed queue is the only queue there is.
- A hand-over carries **at most 128 KB**, and both halves of that number were
  measured. Merging with no limit at all produced 4.9 MB deliveries that took
  235 ms inside one `write`, and `plain` fell to **14** renders a second. Not
  merging at all gave libghostty-vt a kilobyte per write, and it spends about half
  a millisecond per `write` on its render state whatever the size — which is where
  45 frames a second became 1.

## What it does now: `renders`, for all three patterns and both engines

Every figure out of **one binary**, 1920×1050, 235×47 = 11,045 cells, GPU path,
throwaway bundle id and defaults domain, twelve seconds a mode. "Before" is
`ABYDOS_TERM_BEHIND=queue ABYDOS_TERM_HOLD=bytes`, which restores the rule this item
replaces; the delivery model is not switchable, so the last table separates the two.
Loads printed with every run, 4.9–9.8 over ten cores throughout.

**Our engine, with 0489 and 0488 both back in:**

| pattern | renders | cells/render | rows/render | parse | stale | end to end |
|---|---|---|---|---|---|---|
| `plain` | **60** | 11,045 | 47 | 517 ms | 10 ms | 46.4 MB/s |
| `fire` | **60** | 11,045 | 47 | 410 ms | 14 ms | 58.2 MB/s |
| `prompt` | **10 of 10** | **235** | **1** | 1 ms | 3 ms | held to 10 fps |

`prompt` is the pattern that did not exist: the prompt line rewritten under cursor-up
at ten frames a second, with the recalled command changing length every frame. It is
held to ten because a shell rewrites its prompt when somebody presses a key, and a
hundred thousand rewrites a second is a picture of nothing.

**Where it started**, on main with both reverts in, before any of this:

| pattern | engine | renders | parse | build | measured on |
|---|---|---|---|---|---|
| `fire` | ours | 38–45 | 502–527 ms | 226–265 ms | main, both reverts in |
| `fire` | libghostty-vt | **1** | 686–697 ms | 5–6 ms | main, both reverts in |
| `fire` | ours | 41–42 | 512–519 ms | 230–234 ms | old rule, old back-pressure |
| `plain` | ours | **1–2** | 628–657 ms | 2–4 ms | old rule, old back-pressure |

The last two are the old rule restored by environment variable on a build that had
the arrival stamp and nothing else, which is why `fire` agrees with the first row to
within the noise. `plain` on libghostty-vt has no "before": by the time it was asked
the delivery model had already changed, and a number that cannot be taken out of the
same binary as its pair is not a number this item is willing to print.

`plain` — a build scrolling past, which is what somebody watches all day — was **one
frame a second on our engine before any of this**, on main, with both fixes out, with
`stale=` reading 284–322 ms every second. It is sixty now, ten milliseconds behind.
That is the finding this item was filed to reach and it was hiding behind the fire,
which was the only pattern anybody was benchmarking.

### Which of the two changes did which, since both were needed

Same final binary, the rule switched by environment variable:

| | our engine, `plain` | our engine, `fire` | libghostty-vt, `fire` |
|---|---|---|---|
| the old rule | 60 | 60 | **1** (5.8 MB/s) |
| the new rule | 60 | 60 | **44–49** (11.4 MB/s) |

**On our engine the delivery model does the work**, and the honest reading is that
with 128 KB hand-overs the queue empties every drain, so "is the queue empty" comes
out right again — by luck, exactly as it did at 43 frames a second before the parser
was fixed. **On an engine slow enough that it never empties, the rule is worth 1
against 45.** Which is the point: the old question was right whenever it happened to
be, and this one is right because it asks about the thing somebody is complaining
about.

## Ruled out on the way

- **Slicing a delivery to fit the frame budget**, which is what "bound the parse work
  per frame" first suggested. Measured and rejected: libghostty-vt costs about half a
  millisecond per `write` whatever the write's size, so smaller pieces multiply a
  fixed cost — at a kilobyte a write it manages 2 MB/s where at 128 KB it manages 130.
  Slicing is a death spiral on any engine with a per-call cost: the estimate of what
  fits the budget falls, so the slices get smaller, so more of them are needed. The
  budget therefore stays a deadline *between* deliveries, one delivery is indivisible,
  and where one delivery does not fit a frame that is the engine's cost to fix — filed
  as **0492**.
- **Merging deliveries with no limit**, the other end of the same dial: 4.9 MB
  hand-overs, one `write` blocking 235 ms, and `plain` down to **14** renders a
  second. 128 KB is between the two and both walls were measured rather than guessed.
- **One merged buffer with one timestamp.** The first version of the merge kept a
  single `Data` and the read time of its oldest byte, and reported bytes read tens of
  milliseconds apart as all being as old as the first — which holds back frames that
  were current. A list of pieces, each stamped, merged only while the last is under
  the limit.
- **Whether the queue is growing or shrinking**, which this item guessed was the most
  promising. It is on the wrong side: `stale=` across a 40,000-frame backlog reads
  1,921,640 ms, 1,585,285, 1,227,283, 855,634, 469,285 — a burst shrinks monotonically,
  and so does a program keeping up.
- **Bytes behind.** Only staleness after dividing by a parse rate that moves ten times
  between patterns and four and a half between builds of the parser.
- **A tighter `liveWindow`.** A quarter of a second is what `burstHoldOff` already was,
  so there is one figure rather than two. Worth knowing for whoever tunes it: the worst
  staleness observed is about twice `backlogHoldTime`, because the reader stops when it
  is a tenth of a second behind and what is already queued still has to be parsed.
- **Time-based back-pressure as the cure for the backlog case.** It is not, and this is
  worth writing down: `enqueue` runs on the main queue, so when the main thread is
  starved — a locked screen, App Nap — nothing that lives there can measure or bound
  anything. That is exactly why the arrival stamp moved to the reading queue: it is the
  one place that still runs, and a stamp taken there makes a main-queue backlog visible
  to the rule even though back-pressure cannot reach it.
- **Chasing `parse=` as a measure of the parser.** It is not one when the drain is
  saturated: 6 ms of budget every 8 ms is 750 ms a second whatever the parser costs, so
  `parse=690ms` was the *duty cycle*. This item's opening "parse went **up** with a
  faster parser" is that, and it does not need explaining by anything about 0489.

### And the cursor-up artefact 0488 went out on

**Not reproduced, in three attempts, all photographed** — see 0488, which has them. A
tenth `ESC[1A ESC[2K` rewrite, a prompt line rewritten in place with the command
changing length so a kept row would leave a tail, and a real login shell with a real
up arrow recalling a command long enough to wrap the line. All three drew correctly
with the row cache on. `abydos-bench --mode prompt` is that pattern permanently, which
is what the revert asked for and what nothing had.

What *is* fixed is the thing indistinguishable from it: a terminal drawn once a second
shows the previous picture for up to a second after every keystroke, and on the engine
the report was made on the pane was doing exactly that.

## Two traps, for whoever measures this next

- **A throwaway defaults domain is not clean.** `AppDelegate` calls
  `Settings.migrate(from: "de.rnd7.ideai")`, which copies the whole of somebody's old
  domain into a fresh bundle identifier unless `appearance`, `terminalScheme` and
  `uiScale` are all already set in it. That is how two items came to be measured on an
  engine nobody chose for them, and it also brings over the window frame — which
  changes the grid, and therefore `cells/render`. Seed those three keys, and pin
  `--window-size`.
- **`renders=0` proves nothing** (0488's trap, still true): AppKit stops the display
  link when the window is behind another.

## Proof

`xcrun swift test` and `make test`, back to back: **2,564 tests in 363 suites, both
runs fully green**, load 7.2 rising to 23 over ten cores during each. Including
`foldComputationIsReasonableOnHugeFile` — 0480's known intermittent — at 8.4 s against
its 10 s bound. The terminal suites on their own,
`Terminal|Ghostty|Icat|UnicodePlaceholder|LigatureRun`, 331 tests in 48 suites, green
after each of the three changes separately. No terminal test was edited except for the
second parameter `onOutput` now carries.

`make warnings`: no warnings in this repository's Swift. `make build CONFIG=debug`:
builds.

The counts are 2,564 and 363 against the 2,555 and 362 this item was handed, and the
difference is the two tests added here for the delivery contract plus 0488's own tests
coming back with it.

## Steps

- [x] Say what "stale" should mean, in something measurable, and why the
      alternatives lose — seconds behind; bytes and the derivative both ruled out
      with numbers above
- [x] The screen draws at the display's rate while a program keeps up
- [x] A genuine backlog — a locked screen, an app switch — still does not replay
      history — 40,000 frames, **7 draws**, the same as the old rule
- [x] A program that writes one frame and exits still has it drawn (0468) —
      `runsACommandAndCapturesOutput` and
      `aCommandThatHasFinishedStillShowsWhatItPrinted` are that guard and are green,
      and the time limit on the backlog *shortens* the exposure they were written
      for: the reader now resumes after a tenth of a second rather than after four
      megabytes have been parsed
- [x] `renders` measured for `fire`, `plain` and a prompt rewritten under cursor-up —
      the third of those needed a pattern, so `abydos-bench --mode prompt` is one now
- [x] Re-land 0489, then 0488, each with `renders` before and after
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` says what the project now does
