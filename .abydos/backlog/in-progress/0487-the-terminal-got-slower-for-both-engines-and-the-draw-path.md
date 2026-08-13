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

2026-08-13 13:45 — cause confirmed, no code change needed; about 30 minutes of writing up left

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

## The build the report was made against does not contain 0485

This is the finding that reframes the item, and it is evidence rather than an
argument:

    /Applications/Abydos.app  CFBundleVersion 1091
                              AbydosCommit    d593dbe
                              installed       2026-08-12 18:32
                              running since   2026-08-12 18:33 (pid 2768)

    0485 merged at 3066fe9 —  2026-08-13 11:56

`d593dbe` is an ancestor of the 0485 merge by seventeen and a half hours, two
commits before the 0.2.0 release commit. **The app the report was made against is
0485's ancestor.** Nothing 0485 did can be what was felt, and no measurement of
0485 could have found it.

And "no matter if I enable or disable ghostty" has a much simpler explanation
than two engines costing the same. In build 1091 the setting is **0474's**:
registered, present in Settings, and wired to nothing but `--report-geometry`,
which prints `libghostty-vt(requested,not-wired)` when it is on. 0485 is the
commit that made the setting mean something. So in that build enabling and
disabling it *cannot* change anything, because there is only one engine in it —
and that is the same sentence the item read as evidence about two. The user's own
defaults say which configuration it was felt in: `terminalGPURendering = 1`,
`terminalGhosttyEngine = 0`.

## The felt path, measured in the app, on both builds

With the seam costing microseconds inside a millisecond frame, the only
measurement left that could have mattered was of the thing that is felt.
`--type-latency 60` types sixty keys at a human rate through `keyDown`, and
`InputProbe` splits each keystroke three ways: the shell echoing the byte back,
our parse, and our draw. Release builds of **1091 (the installed commit)** and
**1109 (HEAD, with 0485)**, same machine, same throwaway defaults domain, same
throwaway project — and every run guarded by `--report-cwd` printing that
project's path before anything was driven, because a set of timings taken on
whatever was open last is worse than none.

Medians in milliseconds, sixty samples each, load 3.2–6.7 over ten cores
(0.3–0.7 per core):

| echo / parse / **draw** / total | 1091, before 0485 | 1109, with 0485 |
|---|---|---|
| GPU on — the reported configuration | 0.31 / 3.09 / **3.27** / 6.69 | 0.31 / 3.08 / **3.22** / 6.70 |
| GPU off — the CoreGraphics path | 0.34 / 3.09 / **0.80** / 4.17 | 0.30 / 3.08 / **0.77** / 4.14 |

**Identical within noise, on both render paths, and HEAD is a hair faster.** A
keystroke reaches the screen in under seven milliseconds on either build. So 0485
costs the app's draw nothing measurable — and the installed build's terminal is
not slow either, on this machine, at this load.

The burst driver says the same about a program repainting rather than a person
typing. `--burst 600`, six hundred full-screen repaints of a 46×235 grid enqueued
at once: the GPU path answered with **seven renders**, 2.6 ms of build each, and
the CoreGraphics path with **two draws** — `RedrawThrottle` coalescing a burst
into the picture at the end of it, which is what it is for.

## So what is it? None of the five, and not in this code

Said plainly, because a fix aimed at the wrong thing would be worse than saying
so. One of the five candidates — the per-write snapshot cache — explains the
*evidence* completely, by explaining why the number moved without anything
getting slower. The other four are ruled out below. And the reported slowdown is
not in the diff this item is about, because that diff is not in the build it was
reported from.

What is left for whoever picks this up, in the order worth doing:

- **Take the reading on the build that is installed**, with
  `ABYDOS_INPUT_PROBE=1 … --type-latency 60`. The figures above say what this
  machine gives at 0.3–0.7 per core; a median much worse than 6.7 ms while it
  feels slow is the first real evidence there will have been.
- **`~/Library/Logs/Abydos/stalls.log` has one terminal stall for the whole of
  2026-08-13** — `83 ms terminal parse cpu 100%` — and no `terminal draw` stall
  at all. All fifty-six terminal stalls in that log are older than the installed
  build. That is not proof of nothing: `StallWatch.threshold` is 50 ms, so a
  terminal uniformly twice as slow per keystroke that never crosses it is
  invisible there. Which is exactly why the instrument for this is the latency
  probe and not the stall log.
- **The build was installed 2026-08-12 18:32 and has been running since 18:33.**
  If it felt fine on the 12th and slow on the 13th with no new build between,
  nothing in this repository changed underneath it and the question is what else
  on the machine did.

## What was ruled out on the way

- **Existential dispatch through the seam** — the item's hypothesis, and the best
  fit for its evidence. Measured at **1.11× of a 2.2 µs frame: 0.22 µs**, thirteen
  microseconds a second at 60 Hz. Real, and four orders of magnitude from
  anything felt. `drawPathCost` goes on measuring it.
- **`takeDirtyRange` reporting more than it used to.** 0485 edited neither
  `TerminalEmulator.swift` nor the dirty machinery in `TerminalScreen.swift` —
  neither is in its diff — and `invalidateChangedRows` is untouched by it. Now
  asserted rather than only read: `TerminalDirtyRangeTests` says a printed line
  dirties two rows out of five thousand, and a discarded line dirties the
  document.
- **The snapshot cache being invalidated more often than it is used.** Not a
  cost, and the *reason this item exists*: the cache is why 0485 put a write into
  `gridSnapshotCost`, and that write is the 2.8×. Measured both ways above. For
  libghostty-vt the cache is worth 80× a frame — 160 µs after a write against
  2 µs with nothing new.
- **The extension moving from `TerminalScreen` to `TerminalGridReading`**, and
  "no body changed" being true of the source and not of the generated code. It is
  inside the 1.11×: every one of those bodies is reached through the same witness
  table the rest of the frame is, and the whole frame is 2.2 µs.
- **Which build, in the sense the item meant it** — release rather than debug.
  Everything here is release: the benches and both app builds. The same question
  in the sense it did *not* mean turned out to be the answer, which is worth the
  note. "Which build" was on the list as "reproduce in release"; the fact worth
  having was which build was *installed*.
- **A before-and-after app measurement of the seam alone.** Deliberately not
  taken, on 0472's arithmetic rather than out of laziness: the effect is 0.22 µs
  and the spread of the app's own draw is 0.36 ms to 15 ms. The harness is four
  orders of magnitude over the effect, so any pair of app numbers quoted as
  "before and after the seam" would be reporting scheduling noise — which is the
  exact error this item was filed on. The seam is measured where it can be, in
  `drawPathCost`; the app is measured for the question it can answer, which is
  whether the two builds differ at all. They do not.
- **Fixing the draw path.** Nothing in `Sources/` was changed. The item's own
  proposed fix — one concrete snapshot per frame, or the view generic over the
  engine — would buy 0.22 µs a frame for thirty-two call sites in the file 0485
  most wanted left recognisable. A change that size wants a reason larger than a
  number four orders of magnitude under the complaint.

## One real slowdown found on the way, for anybody who turns the setting on

Not the reported fault — the report has the setting off — but measured, and worth
an item of its own. `GhosttyTerminalEngine.afterWrite` sets
`dirty = 0...(totalLineCount - 1)` after **every** write, with an honest comment
saying why: libghostty-vt tracks dirtiness per row inside its render state and
this engine does not read that yet. With `terminalGPURendering` off the dirty
range is what the CoreGraphics path draws, and `invalidateChangedRows` gives up
and repaints the whole viewport once the range passes half of it — which this one
does immediately. So under libghostty-vt with the GPU off, every batch of output
repaints the screen where ours repaints two rows.

`TerminalDirtyRangeTests` holds only our engine to the two-row claim for that
reason: under libghostty-vt it is currently false by design rather than by
accident. Whoever wires that up has a number to beat and a test to widen.

## Steps

- [x] Reproduce it as a number, in a release build, with the setting off —
      both of the table's numbers, from one binary at HEAD. It is the bench
- [x] Say what the draw path costs per frame before and after 0485 —
      2.10 µs concrete, 2.32 µs through the seam, on a 16,700 µs frame
- [x] Confirm or kill the existential hypothesis with a measurement, not a
      reading — **killed**, at 1.11× of a 2 µs frame
- [x] Which build the report was made against, and what is in it — 1091,
      `d593dbe`, an ancestor of the 0485 merge. It does not contain 0485
- [x] Check `takeDirtyRange` is still reporting what it used to — it is, and
      `TerminalDirtyRangeTests` says so now rather than nobody saying so
- [x] Measure the felt path in the app itself, in the configuration the report
      was made in, rather than only the seam in a test — 1091 against 1109,
      both render paths, keystroke to screen under 7 ms on both
- [ ] Fix it with the option intact, and say what the number is afterwards
- [x] A bench that would have caught this — the suite measured writes and not draws,
      which is why a 2.8× on the one draw number was the only clue
- [x] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed; a performance fix may need no
      delta, and saying so is an answer

Two will not be ticked, and neither is work left undone.

**There is nothing to fix.** The draw path is not slower — the benchmark's body
changed and the build the report came from does not contain the change it was
blamed on. Everything this item added is a test, a bench and a `make` verb; the
one thing it would have changed in `Sources/` is a 0.22 µs saving across
thirty-two call sites, and it was measured and declined above rather than done
because it was on the list.

**And no spec delta**, for the same reason 0472 had none: `spec/` is the account
of what the *program* does, and nothing the program does changed. A requirement
about how this repository measures its own draw path does not belong in it.
