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

## Steps

- [ ] Say what `ghostty_render_state_update` costs, per call, with a number
- [ ] Find out whether anything reads the render state, and stop updating it on the
      parse path if nothing does
- [ ] A dirty range from libghostty-vt's per-row dirtiness, so 0488's row cache
      applies to it too
- [ ] `renders` and end-to-end MB/s for `fire`, `plain` and `prompt`, both engines,
      out of one binary
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed
