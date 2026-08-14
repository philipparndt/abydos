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

`ABYDOS_BENCH=1 ABYDOS_BENCH_ENGINE=abydos xcrun swift test -c release`, the two builds
run back to back in one sitting so the loads are comparable. MB/s, before at load 4.8
over 10 cores (0.5 per core), after at 3.7 (0.4):

| bench | before | after | |
|---|---|---|---|
| **plain log output** | **23.9** | **108.8** | **4.6×** |
| **plain, history full** | **23.6** | **116.1** | **4.9×** |
| ascii only | 43.6 | 278.1 | **6.4×** |
| wide-ish glyphs only | 41.4 | 77.4 | 1.9× |
| colour changes only | 181.9 | 211.5 | 1.16× |
| doom fire | 135.2 | 168.8 | 1.25× |

Three consecutive runs of the finished build, load 0.4 per core throughout, so the
spread is on the record rather than one figure being quoted: plain **115.1 / 113.4 /
111.0**, plain-history **115.6 / 115.6 / 113.6**, ascii **283.9 / 283.7 / 284.8**,
wide **80.2 / 80.4 / 80.6**, colour **211.1 / 210.4 / 210.5**, fire **168.3 / 168.8 /
169.6**. A couple of per cent, against effects of two to six times.

For scale against the item's own table: `plain` was 23.4 against libghostty-vt's 337.9,
a factor of fourteen. It is a factor of three now, and none of what closed it was in
the parser.

## And end to end, in the app, over a pty — which is where the number is largest

The rule this item sets is that a win in-process has to be shown in the app or admitted
not to be one. `abydos-bench` in a real pane of a release build, `ABYDOS_METAL_PROBE=1`,
twelve seconds a mode, the two builds differing only in these two files. Every run is
guarded: the first thing the pane runs is `pwd` into a file, and the driver refuses to
read a measurement unless that file names the throwaway project it was told to open —
the shell in the pane saying where it is, which is what `abydos-bench` inherits.

`parse=` is the probe's own figure: how many milliseconds of each second the app spent
inside `TerminalEmulator.write`.

| mode | parse, before | parse, after | end to end |
|---|---|---|---|
| **plain log output** | **698 ms/s** | **12 ms/s** | 3.3 → 3.3 MB/s |
| **plain, history full** | **700 ms/s** | **10 ms/s** | 3.3 → 3.3 MB/s |
| doom fire | 99 ms/s | 83 ms/s | 11.2 → 11.2 MB/s |

Loads 0.8–1.3 per core, printed with each run.

**Ordinary log output was costing the app seven tenths of every second in the parser.
It costs one hundredth now.** That is the same shape as the 505 ms this item was filed
about, on the pattern somebody watches all day rather than on a benchmark — and it is a
far larger effect in the app than in the test, because the app's grid is 235×46 rather
than 100×40, so the row it allocated and freed per newline was two and a third times
wider.

**And the end-to-end MB/s did not move, on any mode.** Said plainly, because this item's
own rule says to: at 3.3 MB/s arriving against a parser that manages a hundred and ten,
**the parser was never what limited plain output end to end** — `RedrawThrottle`, the
read loop and the 6 ms `parseBudget` are. What the fix bought the app is not more bytes
through; it is seven tenths of a second of main thread back, which is what everything
else in the app was waiting for.

Two things this measurement is not. It is **not** comparable with the item's 505 ms in
absolute terms: that was taken with `terminalGPURendering` on, and in this harness the
Metal path never engaged (`renders=0` in every second of every run), so these figures
are the CoreGraphics path. Why the setting did not take is not chased here — the GPU
path is 0488's half of the frame, and `parse=` is measured on the way in and is the same
figure either way. And the fire's 99 → 83 is **1.19×**, which agrees with the
in-process 1.25× and is nothing like a halving; the fire is the one pattern this fix
does least for, because the fire homes the cursor and barely scrolls.

## The item's "microsecond per cell" is an artefact of the arithmetic

Worth writing down, because the title rests on it. The probe reports `renders` and
`parse` per second, and `cells/render` is the size of the grid — so `parse` divided by
`renders × cells` is only a per-cell cost if every parsed frame was also drawn. It was
not: the fire outruns the draw and the app coalesces. At the 456 µs a 40×100 fire frame
measures in-process, 505 ms of parsing is about **three hundred and seventy frames**,
not forty-three — and 505 ms over 370 × 11,750 cells is **115 ns a cell**, which is what
the bench says a truecolour SGR and a glyph cost and is inside the "few hundred
nanoseconds" the item asks for. The microsecond was 505 ms divided by the frames that
reached the screen instead of the frames that reached the parser.

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

## What is left, and the number that says how much

The parse path is now, on plain output, one thing: **blanking the row that arrives at the
bottom of the screen.** A profile of the finished build puts 6,045 of `lineFeed`'s 7,161
samples in `TerminalScreen.blank` — 84 per cent — and none of them is reference counting
any more. They are stores.

A `TerminalCell` is about forty-eight bytes: a `UInt32` scalar, a sixteen-byte
`String?`, a `TerminalAttributes` of two colour enums, eight `Bool`s and a `UInt16`, and
another `Bool`. Blanking a 235-column row therefore writes about eleven kilobytes, per
newline. **That is the whole of what is left**, and it is the *width* of the cell rather
than its non-triviality — which is worth knowing before anybody spends a day on the
obvious idea:

**Measured, as a throwaway experiment and then reverted.** `combining` was replaced by a
computed property returning nil, making `TerminalCell` trivially copyable — the change a
future item would make properly by interning clusters out of the cell. Release, same
sitting: plain **107.7 → 134.1** and ascii **271.8 → 295.4**. So making the cell trivial
is worth about **a quarter on plain output and a tenth on ascii** — real, and not the
several times that removing an allocation was. Shrinking the cell would be worth more
than making it trivial, and both need `combining` to leave the struct, which changes a
public type read by `TerminalView`, the Metal renderer, `TerminalSelection` and
`UnicodePlaceholder`. That is an item of its own and it now has a number to beat.

## Proof

**Six runs of the full suite, 2,555 tests in 362 suites. Four fully green.** The two
reds are the same single test both times, and it is not this item's:

    foldComputationIsReasonableOnHugeFile() — Expectation failed: elapsed < 10.0
    PerformanceTests.swift:301

That is item **0480**, the known intermittent, and it is a wall-clock bound in a suite
that loads a ten-core machine to eighteen — 0472's argument, in the one place the sweep
left an absolute. Nothing terminal-related failed in any of the six.

The terminal suites on their own — `Terminal|Ghostty|Icat|UnicodePlaceholder|LigatureRun`,
**329 tests in 48 suites** — were run green after each of the two changes, separately, and
**not one test was edited.** That is the constraint this item was given and it is the one
that mattered: 0397, 0404, 0468 and 0476 were all found through that suite.

`make warnings`: no warnings in this repository's Swift. `make build CONFIG=debug`: builds.

## Ruled out on the way

Most of the value of this item is here. Every one of these was measured, not reasoned
about.

- **All five of the item's own candidates for the common path.** Taken in order:
  - *Per-scalar work in `put(scalar:)` that should be per-run.* There is none to find:
    `write` already cuts printable ASCII into runs and `putASCII` puts a whole run in at
    once, and in the profile of the fault it was **136 samples against `lineFeed`'s
    1,302**. The text was never the problem.
  - *A grapheme-breaking pass over text with no combining marks in it.* Not happening.
    `TerminalCell.scalar` is a number precisely so that no `Character` is built per cell,
    `displayWidth` short-circuits ASCII before any Unicode lookup, and `widthCache` holds
    the rest. Nothing in the plain profile is in the Unicode tables at all.
  - *`TerminalCell` copied where it could be written in place.* **This one was right**,
    and `initializeWithCopy for TerminalCell` in the item's profile was the clue — but
    not where it reads as pointing. The copies were not of cells being written by the
    parser; they were of a hundred *blank* cells being allocated and a hundred more being
    freed, per newline, by the scroll.
  - *Bounds or wrap checks per cell rather than per line.* Measured and absent.
    `setASCII` checks the row and the run once and then writes through an unsafe buffer
    pointer; `putASCII` computes the room in the row once per run. Neither shows in a
    profile.
  - *Scrollback eviction doing work proportional to the buffer.* Already fixed before
    this item, and its own comment says so: `ScrollbackBuffer` is a ring, `append` is
    O(1), and eviction is **81 samples of 4,301**. The tell was in the item's own table
    — `plain` and `plain, history full` were 23.4 and 23.6, and an eviction cost
    proportional to five thousand lines could not have produced two numbers that equal.
- **The SGR path, which is step four of this item.** Written, measured, reverted. With
  the common path fixed the fire is 4,000 SGRs and 4,000 glyphs in 456 µs, so SGR is now
  the majority of *that* pattern — and the cheap, safe version of the fix buys nothing
  measurable. `executeCSI`'s switch has `where` clauses on the cases for `q` and `u`
  ahead of the one for `m`, so it cannot all become a jump table and an SGR was walking
  two dozen comparisons to reach its own handler; hoisting SGR to the top of the function
  gave colour **209.9 → 211.2**, fire **167.4 → 170.4** — and `wide-ish glyphs`, which
  contains no CSI sequence whatsoever, moved **76.1 → 80.0** in the same run. The
  control moved as much as the treatment, so the treatment is not distinguishable from
  the machine. Reverted rather than kept: it is a special case in the densest function in
  the file, and 0397, 0404, 0468 and 0476 all came out of that function. **A parser that
  is fast and subtly wrong costs more than the milliseconds are worth**, and a special
  case worth zero milliseconds is all cost.
- **Reusing the evicted line by handing it to something that blanks it and gives it
  back.** The obvious spelling, and it made things **worse: plain 23.4 → 16.7 MB/s.**
  While the call is running, the caller's local and the callee's binding are two
  references to one array, so the write copies the row before touching it — a copy *and*
  a fill where the old code did an allocation and a fill. The evicted line goes into the
  grid slot first and the local is dropped before anything is written, and that is not
  style: it is the difference between 16.7 and 108.8.
- **Handing the retired line to `append` directly instead of through a local**, so that
  a screen with no history — the alternate screen, which is what every full-screen
  program runs on — cannot hold a second reference to the row about to be blanked.
  `ScrollbackBuffer.append` returns the caller's own line when the capacity is zero, so
  `let retired` still being in scope reads like the copy-on-write trap that cost 23.4 →
  16.7 above. **It is not one.** Measured on the plain pattern with `ESC[?1049h` in front
  of it, back to back: **145.9 MB/s with the local, 141.6 without** — and the run without
  it had the quieter machine (0.7 per core against 1.2). The optimiser is already ending
  that lifetime at the call. Reverted, because 2,555 tests are green on the version with
  it and an unmeasurable change to this function is not worth a rebuild.

  Two things worth keeping from having looked, though. **`firebench` emits `ESC[?1049h`
  and the in-process `doomFire` bench does not**, so the bench and the fire somebody
  actually runs scroll through different branches — the bench through the ring and the
  eviction, the real fire through neither. And plain output on the alternate screen runs
  at **146 MB/s against 116 on the main screen**, because with no history there is no ring
  write and nothing to evict. Neither is a defect; both are things the next person
  measuring this would otherwise assume the other way round.
- **`swift build --build-tests -c release`**, which is how these benches look as though
  they should be built. It fails in this package with `unable to resolve Swift module
  dependency to a compatible module: 'AbydosKit'` — `@testable` needs `-enable-testing`
  and that spelling does not pass it. `swift test -c release` does, and works. Nothing to
  fix; an hour not to lose.
- **The engine seam and libghostty-vt**, both already ruled out by the item and neither
  revisited. Nothing here went near either.

## Re-landed under 0491, and this time the throughput moved

Reverted on 2026-08-14 on the belief that it had frozen the screen, and that was
wrong twice over: the collapse to one frame a second was measured on libghostty-vt
against a baseline measured on this engine (see 0491), and the redraw policy that
produced it was wrong independently of anything here.

Back in on top of 0491's policy, our engine, 1920×1050, 11,750 cells, GPU path,
load 6.9–7.4 over ten cores, `ABYDOS_METAL_PROBE=1`:

| mode | | renders | parse | stale | end to end |
|---|---|---|---|---|---|
| **plain** | without 0489 | 51–56 | 695 ms | 284–307 ms | 13.4 MB/s |
| | **with 0489** | **60** | 517 ms | **10 ms** | **46.1 MB/s** |
| fire | without 0489 | 60 | 500 ms | 23 ms | 59.0 MB/s |
| | **with 0489** | **60** | 407 ms | 14 ms | 58.0 MB/s |

**This item said its end-to-end throughput did not move on any mode, and said why:
`RedrawThrottle`, the read loop and the 6 ms `parseBudget` were the limit, not the
parser.** They were. With those fixed, plain output goes 13.4 → 46.1 MB/s — three
and a half times — and the picture is ten milliseconds behind the program instead of
three hundred. The 4.6× measured in-process is finally visible in the app, which is
what this item's own rule asked for.

The 40,000-frame backlog draws **3** pictures with this in, against 7 without: a
faster parser gets through somebody's buffered afternoon sooner, so there are fewer
heartbeats on the way. Nothing about the backlog case is weakened by it.

## Steps

- [x] Say where the microsecond goes, from a profile of the parser rather than a guess
      — 97 per cent of it is in `lineFeed`, and half of that is `malloc` and half is
      `free`, both of them per-cell because `TerminalCell` holds a `String?`. And the
      microsecond itself is an artefact: 505 ms over the frames that were *drawn*
      rather than the frames that were parsed. Per cell it was 115 ns
- [x] Find why plain text is six times slower than colour changes, which is backwards
      — because plain text line-feeds every fifty bytes and colour changes every
      fifteen hundred, and a scroll cost 1.7 µs against 7.7 ns for a cell of text
- [x] Fix what that turns out to be, measured in-process and end to end — in-process
      23.9 → 108.8 MB/s on plain; in the app, parse 698 → 12 ms of every second. The
      end-to-end *throughput* did not move and it is said above why: the parser was
      not what limited it
- [x] The SGR path, if it is still worth it once the common path is fixed — measured
      and **declined**, with the control moving as far as the treatment. See above
- [x] No behaviour changes: the emulator suite is the guard, and every terminal test
      passes unchanged
- [x] Write down here what was ruled out on the way
- [ ] No spec delta expected — this is speed, not behaviour

The last one will not be ticked, for 0472's and 0487's reason: `spec/` is the account of
what the program does, and nothing the program does changed. Every terminal test asserts
exactly what it asserted before and none of them was touched.
