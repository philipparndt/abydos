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

## Steps

- [ ] Say what "stale" should mean, in something measurable, and why the alternatives lose
- [ ] The screen draws at the display's rate while a program keeps up
- [ ] A genuine backlog — a locked screen, an app switch — still does not replay history
- [ ] A program that writes one frame and exits still has it drawn (0468)
- [ ] `renders` measured for `fire`, `plain` and a prompt rewritten under cursor-up
- [ ] Re-land 0489, then 0488, each with `renders` before and after
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does
