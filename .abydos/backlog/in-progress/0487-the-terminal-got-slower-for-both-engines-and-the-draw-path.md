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

## Steps

- [ ] Reproduce it as a number, in a release build, with the setting off
- [ ] Say what the draw path costs per frame before and after 0485
- [ ] Confirm or kill the existential hypothesis with a measurement, not a reading
- [ ] Check `takeDirtyRange` is still reporting what it used to
- [ ] Fix it with the option intact, and say what the number is afterwards
- [ ] A bench that would have caught this — the suite measured writes and not draws,
      which is why a 2.8× on the one draw number was the only clue
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` only if behaviour changed; a performance fix may need no
      delta, and saying so is an answer
