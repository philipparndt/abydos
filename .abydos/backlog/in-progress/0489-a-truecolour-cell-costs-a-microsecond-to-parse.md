# 489. A truecolour cell costs a microsecond to parse

`ABYDOS_METAL_PROBE=1` during a fire benchmark:

    renders=43  cells/render=11750  parse=505ms  build=250ms  drawable=1ms  encode=8ms

**Parse is 505 ms of every second** — two thirds of the busy time, and the largest
single cost in the terminal. At 43 renders of 11,750 cells that is roughly **a
microsecond per cell**, for one `ESC[38;2;R;G;Bm` and one glyph. A few hundred
nanoseconds is what that should cost.

## Where it is not

**It is not the engine seam** (0487: 1.09–1.11× through the protocol, 0.22 µs on a
16,700 µs frame) and **it is not libghostty-vt's to fix for this pattern.** Measured
side by side, release, same machine:

| bench | ours | libghostty-vt |
|---|---|---|
| plain log output | 23.4 MB/s | **337.9** |
| plain, history full | 23.6 | **337.7** |
| wide-ish glyphs | 40.8 | **1102.6** |
| colour changes only | 179.4 | 371.0 |
| **doom fire** | **136.2** | 162.8 |

On the fire, switching engines buys 1.2×. **On ordinary log output it buys fourteen**,
and that is the number that matters for a build scrolling past — which is what somebody
actually watches all day. Both facts belong in this item because they point at
different work: the fire says *our SGR path is slow*, and `plain` says *our common
path is slower still*.

## The shape of the question

23.4 MB/s on plain text against 179.4 on colour changes is backwards. Plain text is the
path with no escape parsing at all — it should be the fastest thing the engine does,
and it is six times slower than the path that parses an escape per cell. **Something
specific is wrong in the common path**, and finding what is more valuable than shaving
the SGR path, because it is the case every terminal spends its life in.

Candidates, none confirmed: per-scalar work in `put(scalar:)` that should be per-run;
a grapheme-breaking pass over text that has no combining marks in it; `TerminalCell`
being copied where it could be written in place (`initializeWithCopy for TerminalCell`
shows up in the profile); bounds or wrap checks per cell rather than per line;
scrollback eviction doing work proportional to the buffer.

For the SGR path specifically: `consumeCSI`, `applySGR`, `resetParameters` and the
parameter accumulation are all in the profile below `TerminalEmulator.write`, and none
of it has ever been looked at with a number in hand.

## How to measure it

`abydos-bench` now runs all seven patterns for ten seconds each, and
`TerminalThroughputTests` measures the same byte patterns in-process with
`ABYDOS_BENCH=1 … -c release`. Between them, a change can be attributed to the parser
rather than to the app: **if the in-process number moves and the end-to-end one does
not, the win was somewhere else.**

## The number to beat

505 ms/s. Halving it takes the frame from about 17.5 ms to 11.6 and, with 0488's build
saving beside it, under the 8.3 ms that 120 Hz needs. Reaching parity with libghostty
on `plain` would be a fourteenfold change in the case that matters most and is almost
certainly not achievable by tuning — but finding *why* the gap is that shape probably is.

## Steps

- [ ] Say where the microsecond goes, from a profile of the parser rather than a guess
- [ ] Find why plain text is six times slower than colour changes, which is backwards
- [ ] Fix what that turns out to be, measured in-process and end to end
- [ ] The SGR path, if it is still worth it once the common path is fixed
- [ ] No behaviour changes: the emulator suite is the guard, and every terminal test
      passes unchanged
- [ ] Write down here what was ruled out on the way
- [ ] No spec delta expected — this is speed, not behaviour
