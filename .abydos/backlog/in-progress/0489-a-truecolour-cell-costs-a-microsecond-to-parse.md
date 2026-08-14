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

## The answer: it is not the parser at all. It is what a newline costs

**Plain text is slower than colour changes because plain text scrolls and colour
changes do not**, and one scroll cost 1.7 µs where a whole cell of text cost 8 ns.

That is arithmetic anybody can check against this item's own table, and it is worth
doing before the profile, because it says where to point the profiler:

| bench | bytes per scroll | MB/s (before) |
|---|---|---|
| plain log output | **≈50** | 23.4 |
| ascii only | ≈102 | 44.1 |
| wide-ish glyphs only | ≈300 | 41.4 |
| colour changes only | **≈1,500** | 178.9 |
| doom fire | ≈72,000 (`ESC[H`, one per frame) | 135.5 |

`plainOutput` is two thousand lines of about fifty bytes each, so it line-feeds every
fifty bytes. `fireComponents`'s colour bench is forty rows of a hundred truecolour
SGRs, so it line-feeds every fifteen hundred. **Thirty times the newlines per byte**,
and the two rates differ by seven and a half. Solving the three benches as three
equations in three unknowns — cost per scroll, per ASCII cell, per SGR — gives:

    a scroll        1.7 µs
    an ASCII cell   7.7 ns
    a truecolour SGR  67 ns

A scroll cost **two hundred and twenty times an ASCII cell.** Nothing about parsing an
escape sequence is slow here. `plain` is the pattern that scrolls, and that is all the
six times is.

### And what the 1.7 µs was: a `String?` on a cell nobody put a string on

`sample`, release build, `plainOutputWithFullScrollback` under
`ABYDOS_BENCH_SECONDS=6`, ten seconds of samples. Of 1,738 samples in the whole test,
**1,337 are in `TerminalEmulator.write` and 1,302 of those are in `lineFeed()` — 97
per cent.** `putASCII`, the run-at-a-time fast path for the text itself, is 136.

Under `lineFeed` the 1,302 split almost exactly in half, and both halves are the same
fault:

    509  TerminalScreen.scrollUp + 420   →  Array.init(repeating:count:)
                                        →  outlined init with copy of TerminalCell
                                        →  swift_retain, swift_bridgeObjectRetain
    508  TerminalScreen.scrollUp + 148   →  _swift_release_dealloc
                                        →  swift_arrayDestroy
                                        →  outlined destroy of TerminalCell
                                        →  swift_release, swift_bridgeObjectRelease

`TerminalCell` carries `combining: String?` — the whole grapheme cluster, on the rare
cell that is more than its base code point, "nil everywhere else, which is almost
everywhere". That one field makes `TerminalCell` non-trivial to the compiler, so an
array of them can never be memcpy'd or freed in one go. Every scroll therefore:

- **allocated** a fresh hundred-cell row for the bottom of the screen, copying each
  cell in one at a time through `outlined init with copy of TerminalCell`, each
  retaining a string that is nil; and
- **freed** the row that fell out of the far end of history, destroying each cell one
  at a time through `outlined destroy of TerminalCell`, each releasing a string that
  is nil.

So the answer to the item's question is: **a defect, not a design limit.** It is not
the SGR path, not the engine seam, and not the parser — it is a malloc, a free, and
four hundred reference-counting calls, per newline, for a `String?` that is nil in
every cell involved.

### It is a defect that the code already knew about

`ScrollbackBuffer.append` returns the line it displaced, and has said why since it was
written:

> The displaced line is handed back rather than dropped so the caller can reuse its
> storage; a scroll needs a blank line at the bottom anyway, and this one is exactly
> the right size and no longer referenced.

`TerminalScreen.scrollUp` called it as `if scrollback.append(retired) != nil`. **The
one caller threw the storage away and allocated a new row instead.**

## Measured, in-process, before and after

`ABYDOS_BENCH=1 ABYDOS_BENCH_ENGINE=abydos xcrun swift test -c release`, the two
builds run back to back in one sitting so the loads are comparable:

| bench | before | after | |
|---|---|---|---|
| **plain log output** | **23.7** | **67.6** | **2.9×** |
| **plain, history full** | **23.7** | **67.6** | **2.9×** |
| ascii only | 44.1 | 166.9 | **3.8×** |
| wide-ish glyphs only | 41.4 | 74.1 | 1.8× |
| colour changes only | 178.9 | 205.2 | 1.15× |
| doom fire | 135.5 | 169.1 | 1.25× |

MB/s. Before at load 5.5 over 10 cores (0.5 per core), after at 3.1 (0.3 per core) —
both quiet, and the effects are two to four times where the load differs by a fifth.

For scale against the item's own table: `plain` was 23.4 against libghostty-vt's
337.9, a factor of fourteen. It is now a factor of five, and none of what closed it
was in the parser.

## What changed, function by function

Two files, both in `Sources/AbydosKit/Terminal/`, and nothing in `TerminalView` or the
Metal renderer — **0488 is working on those in its own worktree**, so this list is here
to make the merge legible rather than a guess. Every edit is on the parse path.

`TerminalScreen.swift`

- `TerminalCell.write(scalar:attributes:isWideTrailer:)` — **new.** Overwrites a cell a
  field at a time. `cell = TerminalCell(…)` destroys the old cell and copies the new
  one through outlined value witnesses, each releasing and retaining a `combining`
  string that is nil; four stores and a pointer comparison do the same thing with no
  reference counting at all.
- `TerminalScreen.scrollUp(top:bottom:attributes:)` — takes the line
  `ScrollbackBuffer.append` displaces and gives it to the bottom of the screen, instead
  of dropping it and allocating a new row. The evicted line is put into the grid slot
  and the local reference dropped **before** it is blanked, so the grid is its only
  owner and the write happens in place.
- `TerminalScreen.blank(row:columns:attributes:)` — **new.** Blanks part of a row in
  place, marking the row dirty once.
- `TerminalScreen.setScalar(row:column:scalar:attributes:isWideTrailer:)` — **new.**
  `setCell` without the copy.
- `TerminalScreen.setASCII(…)` — writes through `TerminalCell.write`.
- `TerminalScreen.blankLine(attributes:)` — unchanged.

`TerminalEmulator.swift`

- `put(scalar:)` — `screen.setScalar` in place of `screen.setCell(cell: TerminalCell(…))`,
  in all three places (the glyph, its wide trailer, and the space that stops a
  double-width glyph straddling the margin).
- `eraseInLine(mode:)`, `eraseCharacters(_:)` — one `screen.blank(row:columns:)` in
  place of a loop assigning `screen[row].cells[column] = blank`.
- `blankRows(_:)` — **new**, and `eraseInDisplay(mode:)` uses it in place of
  `screen[row] = screen.blankLine(…)` per row.

## Estimate

2026-08-14 09:02 — plain text answered: it is the newline, not the parser — a scroll cost 1.7 us against 7.7 ns for a cell of text, and 97% of it was a malloc and a free per line for a String? that is nil. In-process 23.7 -> 67.6 MB/s on plain. Left: the O(rows) row shift, then end-to-end confirmation

## Steps

- [x] Say where the microsecond goes, from a profile of the parser rather than a guess
      — 97 per cent of it is in `lineFeed`, and half of that is `malloc` and half is
      `free`, both of them per-cell because `TerminalCell` holds a `String?`
- [x] Find why plain text is six times slower than colour changes, which is backwards
      — because plain text line-feeds every fifty bytes and colour changes every
      fifteen hundred, and a scroll cost 1.7 µs against 7.7 ns for a cell of text
- [ ] Fix what that turns out to be, measured in-process and end to end
- [ ] The SGR path, if it is still worth it once the common path is fixed
- [ ] No behaviour changes: the emulator suite is the guard, and every terminal test
      passes unchanged
- [ ] Write down here what was ruled out on the way
- [ ] No spec delta expected — this is speed, not behaviour
