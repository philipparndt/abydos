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

2026-08-14 15:52 — engine and seam done; measuring in the app next

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
- [ ] `renders` and end-to-end MB/s for `fire`, `plain` and `prompt`, both engines,
      out of one binary
- [ ] Say whether the bar was met, and so whether the engine is kept or removed
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed
