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

## Estimate

2026-08-14 14:24 — about two hours left: renders 1 to 51-56 on plain, both re-lands and the suite to go

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
- [ ] `renders` measured for `fire`, `plain` and a prompt rewritten under cursor-up
- [ ] Re-land 0489, then 0488, each with `renders` before and after
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does
