# 487. The terminal got slower for both engines, and the draw path is where it went

> somehow the terminal is now much slower, no matter if I enable or disable ghostty

Reported against an installed build carrying 0485. **"No matter if I enable or
disable" is the important half**: 0485 was supposed to cost the old engine nothing,
and its own report claimed "with the setting off the bytes take the identical
code". The bytes do. The *draw* does not.

## What is already measured, so nobody repeats it

`TerminalThroughputTests` at the 0485 merge against its parent, same machine, load
about 1.0 per core, release build:

| bench | before | after |
|---|---|---|
| doom fire | 123.6 MB/s | 136.2 MB/s |
| colour changes only | 169.3 | 179.4 |
| plain log output | 24.0 | 23.4 |
| plain, history full | 24.2 | 23.6 |
| wide-ish glyphs only | 39.8 | 40.8 |
| ascii only | 42.2 | 41.3 |
| **grid snapshot** | **14,355,417 fps ceiling** | **5,060,321** |

So **the parse path is not the regression** — every write bench is within noise and
several are faster. But the snapshot, which is what the *renderer* asks for, does
the same work **2.8× slower**. At 0.000 ms/frame that looks like nothing, and it is
the only number in the suite that moved, which makes it the thread to pull.

## The hypothesis, and it is only that

0485 turned two concrete types into protocol existentials on the path that runs per
row per frame:

- `TerminalView.emulator` was a `TerminalEmulator`; it is now `private let emulator:
  TerminalEngine`, an `AnyObject` existential.
- `grid` was `screen`, a value type read directly; it is now
  `var grid: TerminalGridReading { get }`, and `emulator.grid` appears at **32 call
  sites** in `TerminalView`.

A call through an existential is a witness-table call the optimiser cannot
specialise or inline, and `TerminalScreen` is a value type whose accessors were
previously getting exactly that treatment. Per row, per frame, thirty-two places,
release build — that is the shape of "much slower" without a single byte of parsing
changing.

**Do not assume this is it.** It is consistent with the one number that moved and
with "both engines equally", which is a stronger fit than anything else in the
diff, but a felt slowdown deserves a measurement of the thing that is felt.
`StallWatch` and the stall log already exist for that and were built for exactly
this class of question — item 0446 found a filesystem event walking 45,772 files per
keystroke with them, 667,907 ms down to 10,779.

## Where else to look before settling

- **`takeDirtyRange()`** decides how much is redrawn. If the seam changed what it
  reports, the renderer may be drawing every row where it used to draw one.
- **The snapshot is cached per write** (0485 says so, and made its own bench write a
  byte between reads so as not to time the cache). A cache that is invalidated more
  often than it is used is slower than none.
- **The extension moved from `TerminalScreen` to `TerminalGridReading`**, which 0485
  reported as a widening with "no body changed" — true of the source and not
  necessarily of the code generated for it.
- **Which build.** Confirm the report is against a release build and reproduce there;
  existential dispatch costs far less in debug because nothing was being specialised
  anyway, so a debug measurement could hide it entirely.

## The shape a fix probably has

Make the hot path concrete again without giving up the option: the view holding a
generic over the engine, or the render loop taking one concrete snapshot per frame
and reading rows off *that* rather than through the protocol thirty-two times. The
second is smaller and is closer to what the code did before. **A fix that makes the
option impossible is not a fix** — the setting has to survive.

## Estimate

2026-08-13 13:24 — cause found: the 2.8x was the benchmark, not the code; about an hour left

## The 2.8× is the benchmark, not the code

**Reproduced on one commit, which is what settles it.** `gridSnapshotCost` now
prints its loop both ways, and both of 0487's numbers come out of the same
binary at HEAD:

| the loop | fps ceiling | 0487's table |
|---|---|---|
| `grid` + `line(at:)`, nothing arriving | **14,846,435** | "before" 14,355,417 |
| `write("\u{1B}[?25h")` first, then the same | **5,136,060** | "after" 5,060,321 |

Release build, load 6.2 over ten cores, 0.6 per core.

0485 added that write, at `bad228a`, and said why: the libghostty-vt snapshot is
cached until the next write, so a tight read loop timed the cache. For *our*
engine the snapshot was already free — a retain of a value type — so the write
became the only work in the loop, and adding it slowed the line by 2.8×. Two
different loops, two numbers, one unchanged draw path. **Nothing in that table
is a measurement of the same thing before and after.**

The lesson is not "the bench was wrong" — 0485 needed that write and was right
to add it. It is that a benchmark whose *body* changed cannot be compared across
the change, and this one was compared. Both figures are printed now, each
labelled, so the next person cannot read one against the other by accident.

## What a frame actually costs, and the existential hypothesis is dead

`drawPathCost` measures a frame the way `TerminalView` asks for one —
`takeDirtyRange`, `grid`, `totalLineCount`, forty rows of `line(at:)` and their
cells, `scrollbackCount + cursorRow`, the cursor, the two graphics questions —
and measures the identical frame off the concrete `TerminalEmulator` beside it.
Same release binary, same run, load 6.2 over ten cores (0.6 per core):

| | after a write | nothing new |
|---|---|---|
| ours, through the seam | **2.32 µs/frame** (430,560 fps) | 2.18 µs (459,786) |
| ours, concrete, as before 0485 | **2.10 µs/frame** (476,891 fps) | 1.94 µs (516,605) |
| libghostty-vt, through the seam | 160 µs/frame (6,235 fps) | 2.00 µs (502,135) |

**The seam costs our engine 1.11× a frame: 0.22 µs.** At 60 Hz that is 13 µs a
second, about one part in eighty thousand of one core. Thirty-two existential
call sites, a witness table the optimiser cannot specialise, a value type boxed
on every access — all real, all measured, and all together they come to nothing
a person could feel. **The hypothesis fits the number that moved and is not the
cause of anything**, because the number that moved was not a regression.

The libghostty-vt row is worth keeping for its own reason: 160 µs after a write
and 2 µs with nothing new is the snapshot cache working exactly as 0485 said,
and it is the reason its frame is eighty times ours rather than eighty thousand.

## Steps

- [x] Reproduce it as a number, in a release build, with the setting off —
      both of the table's numbers, from one binary at HEAD. It is the bench
- [x] Say what the draw path costs per frame before and after 0485 —
      2.10 µs concrete, 2.32 µs through the seam, on a 16,700 µs frame
- [x] Confirm or kill the existential hypothesis with a measurement, not a
      reading — **killed**, at 1.11× of a 2 µs frame
- [ ] Which build the report was made against, and what is in it
- [x] Check `takeDirtyRange` is still reporting what it used to — it is, and
      `TerminalDirtyRangeTests` says so now rather than nobody saying so
- [ ] Measure the felt path in the app itself, in the configuration the report
      was made in, rather than only the seam in a test
- [ ] Fix it with the option intact, and say what the number is afterwards
- [x] A bench that would have caught this — the suite measured writes and not draws,
      which is why a 2.8× on the one draw number was the only clue
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed; a performance fix may need no
      delta, and saying so is an answer
