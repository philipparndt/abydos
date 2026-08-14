# 492. libghostty-vt costs half a millisecond per write, whatever the write

Measured in the app while working item 0491, and it is the largest single cost in
the terminal on the engine some people are running. `ABYDOS_METAL_PROBE=1`, one
binary, 1920×1050, 235×47, GPU path, `abydos-bench --mode fire`, load 6–8 over ten
cores. The only difference between the rows is `Settings.terminalGhosttyEngine`:

| engine | end to end | parse | deliveries/s |
|---|---|---|---|
| ours (`TerminalEmulator`) | **58 MB/s** | 500 ms/s | 10,000 |
| libghostty-vt | **1.4 MB/s** | 690 ms/s | 1,400 |

**Forty times slower end to end, in the app**, on an engine that benches *faster*
than ours in process: 0489's table has libghostty-vt at 162.8 MB/s on the fire
against our 136.2, and 337.9 against 23.4 on plain log output.

## Where it is, and it is arithmetic rather than a profile

1,400 deliveries a second, 690 ms of parse: **0.49 ms per `write`**, and the
deliveries averaged about a kilobyte. A kilobyte of the fire is about ten cells. Half
a millisecond for ten cells is not a per-byte cost; it is a fixed cost paid once per
call.

`GhosttyTerminalEngine.afterWrite()` runs on every `write` and calls
`ghostty_render_state_update(renderState, terminal)`, which brings a render state up
to date over the whole grid — 11,000 cells here, and the file says so: "the whole
grid, because libghostty-vt tracks dirtiness per row inside its render state rather
than as a range, and this engine does not use the render state yet." It also sets
`dirty = 0...totalLineCount - 1` per write, which throws away item 0488's row cache
for anything this engine draws.

The proof that it is per-call rather than per-byte is that 0491 changed nothing about
the engine and made it nine times faster by handing it larger writes:

| libghostty-vt, `fire` | renders | end to end |
|---|---|---|
| a kilobyte a write | 1 | 1.4 MB/s |
| up to 128 KB a write | 44–49 | 11.4 MB/s |

The remaining gap to 58 MB/s is the same cost, now paid 1,000 times a second instead
of 1,400.

## Why it matters more than the number suggests

It is off by default, so most people never see it — but it is a setting somebody can
turn on, and when they do the pane is forty times slower than the default and the
row cache is disabled for it. **Two measurements were misattributed to other work
because of it**: 0488 and 0489 were both reverted on numbers taken with this engine
on, against a baseline taken with it off, because a throwaway defaults domain
inherits `de.rnd7.ideai`'s settings (0491 has the trap).

## What to try

- **Do not update the render state on the parse path at all.** Nothing reads it: the
  comment says "this engine does not use the render state yet". If that is still true
  it is pure cost and can move to whoever first asks for a frame.
- **Report a dirty range instead of the whole document.** libghostty-vt tracks
  dirtiness per row; turning that into the range the seam already speaks would also
  give this engine 0488's row cache, which it currently defeats.
- **`refreshState()` and `syncGraphics()` per write**, which are five `ghostty_terminal_get`
  calls and a graphics snapshot. Cheap next to the render state, worth checking once
  it is gone.

## Ruled out already

- **The seam itself.** 0487 measured the protocol at 1.09–1.11×, 0.22 µs on a
  16,700 µs frame. This is not the cost of going through `TerminalEngine`.
- **The library's parser.** 0489 benched it in process at 162–1,102 MB/s depending on
  the pattern. Whatever this is, it is on our side of the FFI call or in a function
  we choose to call.
- **Delivery size, as the fix.** 0491 already merges reads up to 128 KB, which is what
  took this from 1.4 to 11.4 MB/s. Merging further would mean deliveries large enough
  to block a frame — measured at 235 ms for 4.9 MB — so the rest has to come out of
  the per-write cost itself.

## The bar, set before anything was measured

This is a trial with a kill criterion, and the criterion was written down first so
that "improved somewhat" could not be the answer:

> **libghostty-vt reaches at least 0.8× our engine's end-to-end MB/s on `fire` and
> on `plain`, and the same `renders` to within 10% on all three patterns, out of one
> binary with the engine switched by the setting.**
>
> Met: it stays. Not met: the recommendation is to take libghostty-vt out of the
> project entirely — the xcframework, the engine, the setting and the seam if
> nothing else uses it — and put the effort into our own parser instead.

0.8× and not 0.5×, because libghostty-vt's parser is *faster* than ours in process
(0489: 162.8 MB/s against 136.2 on the fire, 337.9 against 23.4 on plain). Anything
below parity therefore means the app-side per-call cost is still what decides the
number, which is exactly what this item is about. A bar of "half as fast" would have
been passed by a fix that left the fault in.

## Estimate

2026-08-14 16:19 — VERDICT: bar met, keep it — 58.0 against our 60.1 MB/s, renders 60/60; writing up

## What the per-call cost actually is, and it is not what the item said

`TerminalThroughputTests.writePathCosts` times each thing `afterWrite` used to do as
the *difference* between a loop that writes and a loop that writes and then does it —
because every one of them is free when nothing has changed since it last ran, and
timed in a tight loop with nothing arriving they would all report the cost of finding
nothing to do. 40×100 with 5,200 lines of history, a kilobyte a write, release, load
19.9 over ten cores:

| per write | measured |
|---|---|
| `ghostty_terminal_vt_write` — the parse itself | **4.67 µs** |
| `refreshState`, the discarded-line anchor, `syncGraphics` | **below noise**, −0.01 µs |
| `ghostty_render_state_update` | **18.48 µs** |
| **a grid snapshot — the visible rows copied** | **194.22 µs** |

So the render state is real — four times the cost of the work it was reacting to —
**and it is the smaller half.** The larger one is not in the engine at all, and this
item did not suspect it: `TerminalView.realignSelectionForDiscardedLines` runs on
every delivery of output and read `emulator.grid.discardedLineCount`. For our engine
`grid` is a retain of a value type and that line is free. For libghostty-vt it copies
every visible cell out of the library, and 0485 built the snapshot cache keyed on the
write count, so a write invalidates it and the next read rebuilds it. **1,400
snapshots a second, eleven thousand cells each, to read one integer.**

Scaled to the pane the item measured — 235×47, 11,045 cells against this bench's
4,000 — that is about 530 µs of snapshot plus 51 µs of render state per write, against
the 490 µs the item derived from `parse=690ms` and 1,400 deliveries. The arithmetic
closes.

### And that is what the C API question comes down to

**Yes, all of it is reachable.** `render.h` exports both layers of dirty tracking —
`GHOSTTY_RENDER_STATE_DATA_DIRTY` for the global `FALSE`/`PARTIAL`/`FULL` state and
`GHOSTTY_RENDER_STATE_ROW_DATA_DIRTY` per row, with setters for both so the caller can
clear them, which its documentation is explicit the update call does not do. Nothing
had to be exported and nothing had to go upstream. 0485's warning that the answer is
sometimes no does not apply here.

## The verdict: the bar was met, and libghostty-vt stays

**`renders` and end to end, one binary, the engine switched by the setting only.**
1920×1050, 235×47 = 11,045 cells, GPU path, throwaway bundle id
`de.rnd7.abydos.item0492` and a throwaway defaults domain with all three migrate keys
seeded, fourteen seconds a mode. **Every run asserts which engine it measured** —
`GEOM 9s: engine=…` off the running app rather than off the setting — and that
`onScreen=yes`, because AppKit stops the display link behind another window and
`renders=0` proves nothing. Load 2.3–9.2 over ten cores, printed with each run.

| pattern | engine | `renders` | cells/render | rows/render | parse | stale | end to end |
|---|---|---|---|---|---|---|---|
| `fire` | ours | **60** | 11,045 | 47 | 427 ms | 14 ms | **60.1 MB/s** |
| `fire` | libghostty-vt | **60** | 11,045 | 47 | 313 ms | 13 ms | **58.0 MB/s** |
| `plain` | ours | **60** | 11,045 | 47 | 540 ms | 11 ms | **48.8 MB/s** |
| `plain` | libghostty-vt | **60** | 11,045 | 47 | 666 ms | 44 ms | **48.8 MB/s** |
| `prompt` | ours | **10 of 10** | **235** | **1** | 1 ms | 3 ms | held to 10 fps |
| `prompt` | libghostty-vt | **10 of 10** | **235** | **1** | 1 ms | 3 ms | held to 10 fps |

**0.96× on the fire, 1.00× on plain, and `renders` identical on all three.** The bar
was 0.8× and parity on `renders`. It stays.

Two things in that table are worth reading twice.

- **`prompt` is `rows/render=1` and `cells/render=235` on libghostty-vt** — item 0488's
  row cache, working on this engine for the first time. It was 47 rows and 11,045 cells
  before, because the engine reported the whole document dirty after every write.
- **`plain` is the same number for both engines**, 48.8 MB/s at 20,107 frames a second,
  and that is a ceiling rather than a tie: it is as fast as the benchmark process can
  write to a pty. Both engines keep up with it. `parse` says which has more headroom
  and it is ours here — 540 ms against 666 — which is 0489's newline fast path, a thing
  we have and they do not.

### And the before, out of the same binary

`ABYDOS_GHOSTTY_PER_WRITE=1` restores both halves of the old behaviour — the render
state on every write with the whole document reported dirty, and `TerminalView` asking
`grid` for the numbers it now gets from `metrics`. It exists because two figures taken
from two builds are two figures, and this project has twice reverted good work on a
pair that could not be compared.

**These six runs were taken with the window occluded** — another application (an
iOS app the machine happens to be running) came to the front between the table above
and this one and would not yield, and twelve retries did not get the screen back. So
`renders` is 0 for every row of this table and is **not printed**, which is the whole
of 0488's trap; what is printed is what the CoreGraphics path and the probe still
measure honestly. Same binary, same pane, one environment variable apart:

| pattern | catch-up | parse | deliveries/s | stale | end to end |
|---|---|---|---|---|---|
| `fire` | per write (before) | 682 ms | **1,268** | 863 ms | **5.2 MB/s** |
| `fire` | per read (after) | 316 ms | **31,100** | 5 ms | **56.5 MB/s** |
| `fire` | ours, same conditions | 444 ms | 27,300 | 6 ms | 61.3 MB/s |
| `plain` | per write (before) | 678 ms | **1,330** | 900 ms | **4.5 MB/s** |
| `plain` | per read (after) | 688 ms | **14,500** | 14 ms | **50.7 MB/s** |
| `prompt` | per write (before) | 21 ms | 10 | 3 ms | held to 10 fps |
| `prompt` | per read (after) | **1 ms** | 10 | 3 ms | held to 10 fps |

**Eleven times on the fire and on plain, out of one binary.** The "before" row
reproduces the numbers this item was filed on to the millisecond — `parse=682ms`,
1,268 deliveries a second, which is the 0.49 ms a write the item derived — so there is
no doubt about what was being fixed.

`stale` is the line to read for somebody sitting in front of it: the picture was **863
milliseconds** out of date on the fire and is now **5**. And `prompt` — a shell
redrawing its prompt line, which is what a keystroke looks like — went from 2.1 ms of
parse per 80-byte delivery to 0.1.

## Steps

- [x] Say what `ghostty_render_state_update` costs, per call, with a number —
      **18.48 µs**, and the snapshot beside it at **194.22 µs**, table above
- [x] Find out whether anything reads the render state, and stop updating it on the
      parse path if nothing does — things do read it (0485 put the visible rows and
      the cursor shape on it), so it moved to the *read* rather than being deleted:
      `bringRenderStateUpToDate`, and `aThousandWritesAndOneReadIsOneRenderStateUpdate`
      is the guard
- [x] A dirty range from libghostty-vt's per-row dirtiness, so 0488's row cache
      applies to it too — `noteDirtyRows`, with `FULL` still answering the whole
      document; four tests, including the two promises ours is held to
- [x] `renders` and end-to-end MB/s for `fire`, `plain` and `prompt`, both engines,
      out of one binary — the table above, with `engine=` asserted and `onScreen=yes`
      on every row of it
- [x] Say whether the bar was met, and so whether the engine is kept or removed —
      **met, and it stays**: 0.96× on the fire, 1.00× on plain, `renders` identical on
      all three against a bar of 0.8× and parity
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` says what the project now does — two requirements added:
      what an engine reports as changed, and the size and history being a cheap
      question that does not copy the screen

## What was ruled out on the way

- **The render state as the whole answer**, which is what this item was filed
  believing. It is 18.48 µs a write and the grid snapshot beside it is 194.22 µs, so
  moving only the render state would have bought about a tenth of the fix and looked
  like a failed hypothesis. The item's arithmetic was right and its attribution was
  ten to one out.
- **Deleting the render state update rather than moving it.** The item's first
  suggestion was that nothing reads it — "this engine does not use the render state
  yet". That comment was 0474's and 0485 made it false: the visible rows of every
  frame come off `render.h`, and `GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE` is
  the *only* place libghostty-vt reports the cursor's shape at all. So it moved to
  the read. Worth knowing that the comment naming it as dead cost was stale by one
  item.
- **Making the grid snapshot lazy** — copying the visible band on the first
  `line(at:)` rather than when the snapshot is made. It would have fixed the
  symptom generally rather than caller by caller, and it is wrong:
  `GhosttyEngineTests.aStaleSnapshotRefusesAHistoryRowItNeverCopied` asserts that
  the band a snapshot copied still reads as the frame it was given after the
  terminal has moved on, and that is the seam's promise — "a snapshot that survives
  later writes". A lazy band would have to *refuse* instead, which is a different
  promise. So the discipline goes on the caller: a snapshot is for drawing a frame,
  and the parse path does not take one. `TerminalMetrics` is what the parse path
  asks instead.
- **Moving `updateDiscardedLineCount` to the read with everything else.** It is
  three FFI calls and `writePathCosts` cannot measure it against a 4.67 µs write, so
  there was nothing to gain — and something to lose: the anchor that counts pruned
  lines has to be re-pinned to the bottom row often, because a burst that scrolls
  further than the whole buffer between two pinnings prunes the anchor itself and
  the count falls back to a lower bound. It stays on the parse path, where it is
  exact.
- **`refreshState` and `syncGraphics` as suspects**, which the item named as "worth
  checking once the render state is gone". Both measure below the noise floor —
  −0.01 µs against a 4.67 µs write, which is to say nothing at all. They moved to
  the read anyway because that is where they belong, but they were never the cost.
- **Narrowing the `FULL` dirty state.** `render.h` reports `FALSE`, `PARTIAL` or
  `FULL`, and `FULL` means "global state changed; renderer should redraw
  everything" with no further detail — a viewport that moved, a palette, a screen
  swap. There is nothing to narrow it *to*, and the whole document is what our own
  engine reports for the same cases. `plain` therefore stays at `rows/render=47` on
  both engines, and `prompt` is where the row cache shows: one row.
- **Five separate members on the seam** — `rows`, `columns`, `totalLineCount`,
  `scrollbackCount`, `discardedLineCount` — instead of one `TerminalMetrics`. Five
  members that shadow `TerminalGridReading`'s names read as a duplicate of it, and
  the thing worth naming is not the numbers but the *distinction*: one question
  costs a copy of the screen and the other does not. A struct with a comment saying
  so is a rule somebody can follow; five properties are five things to get wrong
  again.
- **`renders` for the "before" on the GPU path.** Not taken, and it is not being
  guessed at: another application held the screen for the whole of that half of the
  measurement, AppKit stops the display link behind another window, and a
  `renders=0` printed as though it meant something is 0488's trap and cost this
  project an hour once already. The before/after table says what the probe could
  still measure honestly and omits what it could not. The item's own filed
  `renders=1` and 0491's 44–49 are the GPU figures on record for the old behaviour.

### And where the remaining gap is, for whoever picks this up next

On `plain` libghostty-vt now spends **666 ms** of every second parsing where ours
spends **540**, for the same 48.8 MB/s — both are at the ceiling of what the
benchmark can write to a pty, so the difference is headroom rather than throughput.
That is 0489's newline fast path, which is ours and not theirs: a `\n` in a log line
is the commonest byte in a terminal and we special-case it. It is the one pattern
where our parser is now the faster of the two in the app as well as in the bench, and
it is the thing to send upstream if anybody ever does. **Nothing was opened.**
