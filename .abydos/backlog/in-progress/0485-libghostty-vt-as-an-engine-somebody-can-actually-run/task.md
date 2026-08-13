# 485. libghostty-vt as an engine somebody can actually run

> next we should fully support libghostty-vt so that it is actually usable

0474 built the seam and stopped at the boundary on purpose: the setting is
registered and off, `--report-geometry` prints
`engine=libghostty-vt(requested,not-wired)`, and `TerminalView` still holds a
`TerminalEmulator` rather than a `TerminalEngine`. This item is the wiring, and
**most of it is arithmetic — one part of it is not.**

## What is left, counted

`TerminalView` uses **27 distinct members** of the emulator across 84 call sites.
`TerminalEngine` requires 11 of them. The sixteen that are missing:

    bracketedPaste  colourLookup  cursorShape  encodeArrow  encodeModifiedKey
    encodeMouse  graphics  isSynchronizingOutput  link  mouseTracking  onBell
    onClipboardWrite  onOpenFile  reportsFocus  reportsModifiedKeys  screen

Three of those libghostty-vt answers directly, being the reason its header
advertises them: `encodeArrow`, `encodeModifiedKey` and `encodeMouse` are its key
and mouse *encoding* APIs. Most of the rest are mode and state queries — bracketed
paste, focus reporting, synchronised output, cursor shape, mouse tracking — which a
VT state machine keeps by definition and the C API either exposes or should be
asked to. **`screen` is the one to be careful with**: it is our concrete type at
six call sites, and the protocol already has `grid` for exactly that reason. Those
six are the seam leaking, and they should go.

## The part that is not arithmetic

**Kitty graphics in tmux.** 0468 established that `icat` speaks two protocols and
tmux decides which: a real `t=f` placement outside it, and `U=1` unicode
placeholders inside. libghostty-vt covers the first completely — including
`placement_grid_size`, which does the pixels-to-cells arithmetic 0468 was about —
and only half of the second: the escape is honoured and the virtual placement is
stored and enumerable, but the part that turns placeholder cells into picture
fragments is **not exported**, and the geometry calls actively refuse virtual
placements.

Since this app is used through tmux nearly all the time, an engine that cannot draw
an image there is not "usable" in the sense being asked for. **But the conclusion
0474 drew from that — 1,292 lines of `KittyGraphics` and `UnicodePlaceholder` come
straight back — deserves re-examining, because it assumed we need libghostty-vt to
*draw*.** We do not. We need it to tell us what is in the cells, and it does:
`ghostty_grid_ref_graphemes` returns a cell's codepoints beyond its base, which is
precisely where a placeholder's diacritics live. Our decoder already works from
that.

So the shape worth trying first is **their state machine, their placement store,
our placeholder layer on top** — and if that works, what comes back is much less
than 1,292 lines and none of it is duplicated logic. Prove or disprove it early,
because it decides whether this item is a wiring job or a wiring job plus an
upstream contribution.

## Three more things 0474 measured and left

- **The grid snapshot copies all 5,240 rows instead of the visible 40**: 4.37 ms a
  frame against our 0.000 ms, which gives back the 17× the parser wins. 0474 said
  it is fixable to about 0.03 ms and did not do it.
- **The render path must not use `grid_ref`** — its own documentation forbids it in
  a render loop, and `render.h` is what it points at instead. The current adapter
  uses `grid_ref`, so this is a rewrite of the hot path rather than a tidy-up.
- **`discardedLineCount` has no answer** in libghostty-vt. Ours is used to keep
  absolute row indices stable across scrollback eviction; find out what that costs
  or what replaces it.

## And the finding that inverts the premise

0474 measured that **libghostty-vt reproduces 0404**: it clamps the off-screen
cursor park, so it draws tmux's `(rename-window)` prompt a row too high, over the
pane's output — the exact fault that was reported against our own emulator. Three
escapes reproduce it. The reason is worth keeping in mind for the whole of this
item: this app turns tmux's status bar *off*, which almost nobody does, so a
widely-used engine is well tested **in the configurations many people use**.

That is not an argument against finishing this. It is an argument for the setting
staying off by default until somebody has run it for weeks, and for whatever is
found being sent upstream rather than worked around silently.

## The rule that must not slip

`unimplemented: [String]` already exists on the protocol and its comment is the
contract: a non-empty list is **a promise that the missing parts refuse rather than
draw something plausible.** Every step of this item either empties an entry or
keeps it honest. An engine that silently misrenders is worse than no option,
because the person who notices weeks later cannot tell whether it was the engine,
the seam or a real bug — and they will be told to look at all three.

## Estimate

2026-08-13 11:18 — wired and green; render.h, the differential tests and the write-up left — about two hours

## Step one's answer: yes, and nothing has to be exported upstream

**The tmux image path works behind libghostty-vt with no upstream change.** This
was the question to answer before building anything, and it is a "yes" — so this
is a wiring job and not a wiring job plus an upstream contribution. Six tests in
`GhosttyGraphicsTests` are the evidence and all six passed the first time they
ran.

0474's "no" was right about the API and wrong about what we need from it. It
observed, correctly, that `placement_rect` and `placement_viewport_pos` both
document returning `GHOSTTY_NO_VALUE` for a virtual placement, and that no
`0x10EEEE`, diacritic table or placeholder iterator exists anywhere in the
headers. But **those two calls answer the one question a placeholder picture does
not need asked**: "where on the screen is this placement". For a `U=1` picture
the *cells* are the answer — that is the entire point of the indirection, and why
the picture survives tmux moving it. Everything a placeholder layer actually
needs is exported:

| What our decoder needs | Where it comes from | Confirmed by |
|---|---|---|
| the cell is U+10EEEE | `ghostty_cell_get(CODEPOINT)` | `aPlaceholderCellSurvivesLibghosttysGrid` |
| its row/column diacritics | `ghostty_grid_ref_graphemes` | same |
| the image id, in the raw fg colour | `ghostty_grid_ref_style().fg_color` | same — still `.rgb(0x00,0x04,0xD2)`, unresolved |
| the picture's size in cells | `PLACEMENT_DATA_COLUMNS`/`_ROWS` on the virtual placement | `aVirtualPlacementComesAcrossWithItsSizeInCells` |
| the resolved source rect | `placement_source_rect` — which does **not** refuse virtual placements | same |
| the pixels | `ghostty_kitty_graphics_image(id)` → `WIDTH`/`HEIGHT`/`FORMAT`/`DATA_PTR` | same |

The distinction that makes it work: `placement_grid_size` refuses a virtual
placement, but the **raw** `COLUMNS`/`ROWS` getters do not, and they hold exactly
the `c=46,r=26` that 0468 measured on every one of `icat`'s four runs.
`ghostty_kitty_graphics_image` takes a bare id and does not know or care whether
the placement referring to it is virtual.

### So what comes back is 226 lines, not 1,292

`UnicodePlaceholder` (226) stays — the diacritic table and the fragment
arithmetic — plus `GhosttyGraphicsBridge`, which is new and is not a second
implementation of anything. What does **not** come back is the whole of
`KittyGraphics`' parser: the APC key/value parsing, chunk reassembly, base64,
zlib inflate, id-from-number assignment, the memory budget and LRU eviction, and
the `t=f` pixels-to-cells arithmetic 0468 was about. libghostty-vt does all of
that, and `TerminalImageStore` behind this engine holds a *copy of its answers*
rather than a parse of its own.

### Two things that would have looked like "the library cannot do this"

Both silent, both cost nothing now because they are written down:

- **`icat` sends `f=100`, which is PNG, and libghostty-vt has no PNG decoder.**
  Every PNG transmit is rejected until one is installed through
  `GHOSTTY_SYS_OPT_DECODE_PNG`. `GhosttyPngDecoder` installs the same ImageIO
  path `KittyGraphics.decodePNG` uses, so both engines decode a picture
  identically. `aPngTransmitIsDecodedThroughTheDecoderWeInstall` fails loudly if
  it is ever not installed.
- **CoreGraphics will only draw into a *premultiplied* bitmap, and the kitty
  protocol's RGBA is straight alpha.** So the decode callback undoes the
  premultiplication before handing the buffer over, because the bridge
  premultiplies on the way out and doing it twice draws every partly transparent
  picture too dark. A picture that is subtly wrong is the exact failure this item
  is most concerned with, and it would have been invisible on the opaque
  screenshots `icat` is usually pointed at.

### One thing this required that 0474 said would not happen

`KittyGraphics.swift` — an old-engine file — gained one method,
`TerminalImageStore.adopt(images:placements:virtual:)`. It is purely additive:
nothing in the old engine calls it, no existing member changed, and none of the
parsing or eviction is reachable through it. It exists because `images`,
`placements` and `virtualPlacements` are `private(set)`, so a store cannot be
filled from another file, and 0474 had already ruled out the alternative
(building a `TerminalScreen` from outside) for the same reason. **With the
setting off the old path is byte-identical**, which is the property that
mattered; "no old file edited at all" was a stronger claim than the one being
kept, and this is the cost of it.

## Steps

- [x] Try our placeholder layer on libghostty-vt's grid and placement store, and
      say early whether the tmux image path can work without an upstream export.
      **Yes, with no upstream change** — see above
- [x] The sixteen missing members, with `screen`'s six call sites moved to `grid`
- [x] `TerminalView` holds a `TerminalEngine`, chosen by the setting
- [x] The render path off `grid_ref` and on to `render.h` — the visible rows
      come from the render state; scrollback stays on grid references, which is
      what they are for
- [x] The snapshot costs the visible rows rather than the scrollback
- [x] An answer for `discardedLineCount`, or a reason it is not needed —
      a tracked grid reference anchored to the bottom row after every write
- [x] Every terminal test that can run against both engines does, and the list of
      those that cannot is written here with why
- [x] 0404's three escapes: **not fixed** — the report to send upstream is written
      out below and named in `unimplemented`. Nothing was opened, per the
      instruction not to publish anything
- [x] `unimplemented` is empty, or every entry in it refuses rather than guesses —
      three entries, each a refusal or a named divergence
- [x] Write down here what was ruled out on the way
- [x] `spec/terminal.md` says what the project now does

## What the two engines are held to, and what only one engine is

**Twenty-three tests in `GhosttyEngineTests` and six in `GhosttyGraphicsTests`**
put both engines to the same question, or hold libghostty-vt to the same standard
our own tests hold ours. What they cover: the grid on real captures cell for cell
(`tmux-prompt.bin`, `return-burst.bin`), wide glyphs and combining marks, palette
versus RGB colour, every mode the view reads, each of the four mouse tracking
modes, arrow keys with and without DECCKM, the kitty keyboard protocol, mouse
reporting in both SGR and legacy form, a hyperlink read back off its cell, the
bell, OSC 52, the shape of the snapshot, a stale snapshot's refusal, the
discarded-line count, both kitty protocols, and the render path.

### The ones that cannot run against both, with why

**The existing terminal suites stay single-engine, deliberately.** `TerminalTests`
and the eighteen suites beside it are about 250 tests, and they are the regression
suite for *our* engine — 0397, 0404 and 0468 were all findable because of them.
Three reasons not to fan them out:

- **Many assert on `TerminalEmulator`'s own state, not on the seam.**
  `screen.discardedLineCount` as a line budget, `isParkedBelowScreen`,
  `KittyGraphicsCommand` parsed directly, `TerminalScreen.resize` taking rows from
  the bottom rather than reflowing. There is nothing to compare: libghostty-vt
  reflows on resize and prunes by bytes, and those are design differences the
  engine is *wanted* for.
- **Turning them into parameterised tests means editing every one of them**, and
  the rule this item was given is that the old path does not change. A refactor
  across 250 tests to gain coverage of a second engine would put the first
  engine's safety net through a rewrite, which is the wrong trade in exactly the
  direction the item warns about.
- **The difference is better caught on real bytes than on unit assertions.** Two
  independently written emulators fed a real capture and compared row by row found
  a genuine divergence in twenty minutes (0474, the tmux park), and found two more
  in this item. That is where the value is, and the fixtures are already there.

So: a *differential* suite on captures and on the seam, and the unit suites stay
where they are. Written down because "every terminal test runs against both" is a
thing somebody will otherwise expect to find and not find.

## 0404 under libghostty-vt: the report, not opened

**Not fixed, and it cannot be fixed from here**: the behaviour is inside a
vendored prebuilt `libghostty-vt.a`, and the alternatives are to carry a patch on
a fork of ghostty in `Scripts/build-libghostty-vt.sh` or to work around it in the
adapter. The second is what the item forbids — the adapter cannot know from the
outside whether a `CSI A` after a clamped park meant the park or the clamp — so it
is **named in `unimplemented`** and this is the report for somebody to send.
Nothing was opened; that was the instruction.

> ### Vertical cursor movement counts from a clamped off-screen row
>
> On a five-row screen:
>
>     CSI 6 d      park one row below the screen (VPA to row 6)
>     CSI A        up one
>     X            print
>
> libghostty-vt puts the `X` on **row 4**. It clamps the park to row 5, then
> counts up from the clamp. Counting from the row that was *asked for* puts it on
> row 5.
>
> This is not a hypothetical. **tmux does exactly this** when its status bar is
> off: with `set -g status off` and a command prompt open, tmux parks the terminal
> cursor at `rows + 1` — `CSI 31 d` on a 30-row client, `CSI 25 d` on a 24-row one
> — and then draws the prompt by moving up from the park. On a 24×60 capture of a
> real tmux, libghostty-vt draws `(rename-window) ` on row 22 instead of row 23,
> over output the pane owns and repaints, so the prompt appears and is gone within
> a frame. That was reported as a bug against this project's own emulator (item
> 0404) before the cause was understood.
>
> The rule that fixes it, and the reason it is one row and not general: remember
> that the cursor was asked for the row *one below* the screen, and let `CSI
> A`/`B`/`E`/`F` count from what was asked for rather than from the clamp. One row
> and no further — a program asking for row 999 is guessing at the size of the
> screen rather than parking on the edge of it. The flag lasts until something puts
> the cursor somewhere real: a character drawn, a line fed, a move that lands on
> the screen. That is the same lifetime `pendingWrap` has, one edge over.
>
> Fixtures: `Tests/AbydosKitTests/Fixtures/tmux-prompt-repaint.bin` in this
> project is a 24×60 capture that carries it, and
> `GhosttyEngineTests.theParkRuleIsWhereTheTwoEnginesDiffer` is the three-escape
> version above.
>
> Worth saying why a widely-used engine has this: almost nobody turns tmux's
> status bar off, and with the bar on tmux never parks below a pane. The
> configurations many people use do not ask this question.

## What the three measured leftovers came to

| | 0474 | 0485 |
|---|---|---|
| grid snapshot, 40 rows over 5,200 lines of history | **4.372 ms/frame**, 229 fps ceiling | **0.165 ms/frame**, 6,061 fps ceiling |
| the render path | `grid_ref` per cell over every row, which its own docs forbid | `render.h` for the rows on screen; `grid_ref` for scrollback, which is what it is for |
| `discardedLineCount` | always 0, and `unimplemented` had to admit the scrollbar and selection were wrong | a tracked grid reference anchored to the bottom row; `discarded + kept == produced` is asserted |

Ours stays at 0.000 ms, being a retain of a value type, and nothing about it
changed. **Read the libghostty-vt number carefully**: `gridSnapshotCost` now writes
a byte between reads, because the engine caches its snapshot until the next write
and a tight read loop would have timed the cache and reported a number that was
true and useless. So 0.165 ms is a write *and* a frame — the mode-set, the state
refresh, the discarded-line anchor, the graphics check, the render-state update and
the row copy — and the copy alone is less. Release build, load average 16.1 on ten
cores with another agent building; `make timing` is where a budget lives and this
is not one.

The snapshot is also cached per write, because `TerminalView` reads `emulator.grid`
about twenty times in a frame and for our engine each of those is free. Without the
cache the per-frame cost would have been twenty times what it is, hidden behind an
innocent-looking `.rows`.

The parser throughput on the same run, for completeness and with the same caveat
about load: plain log output 335.0 MB/s against our 23.3, colour changes 366.2
against 176.1, doom fire 161.7 against 134.8, ascii 830.2 against 41.7. The same
shape 0474 measured.

## It runs

`make build CONFIG=debug BUNDLE_ID=de.rnd7.abydos.item0485 PIN_UUID=0` (build
1102), a throwaway defaults domain with `terminalGhosttyEngine` on, and a
throwaway project:

    GEOM 9s: engine=libghostty-vt alt=no rows=10 columns=155 fits=155
             widthOK=yes winsize=10x155 pixels=380x2480 ptyCell=16x38

The pane is drawn by libghostty-vt, the grid matches the pane's width, and the
kernel's winsize carries a real cell size — which is the number `icat` divides to
get its `c=`/`r=`, and the thing 0468 was about. A screenshot showed the project
that was asked for open, and the shell prompt with its colours and cursor drawn by
the new engine. The defaults domain and its plist were deleted afterwards.

## What was ruled out on the way

- **An upstream export for the `U=1` placeholder path.** 0474 said this item was
  either a wiring job or a wiring job plus an upstream contribution. It is the
  first: the placement store and the grid already carry everything a placeholder
  decoder needs, and the two calls that refuse virtual placements answer a
  question a placeholder picture does not ask. Ruled out before anything was
  built, which is what step one was for.
- **libghostty-vt's own key encoder** (`ghostty/vt/key/encoder.h`), which the item
  expected to use. Measured instead: with no protocol requested, and again with
  `MODIFY_OTHER_KEYS_STATE_2` explicitly false and the kitty flags explicitly
  zero, it answers Shift+Enter with `ESC [ 27;2;13 ~` and Ctrl+A with
  `ESC [ 0;5 u`. Both are right for ghostty's own app, which always reports
  modified keys; both would mean a program getting different bytes under the two
  engines, which is the divergence this item exists to prevent. The modes it reads
  are used; the encoding is ours.
- **libghostty-vt's own mouse encoder** (`mouse/encoder.h`). It takes positions in
  *surface pixels* and divides by a cell size — and a cell of no pixels, which is
  what an engine with no view attached has, is documented as invalid input — and it
  keeps motion-deduplication state, while the scroll wheel sends several events at
  one cell on purpose. Five notches would have become one. Its tracking mode and
  output format are read from the terminal; the encoding is ours.
- **`GHOSTTY_TERMINAL_DATA_CURSOR_STYLE` for the cursor shape.** It is not that:
  despite the name it is the cursor's *SGR style*, output type `GhosttyStyle *`, so
  reading it into a four-byte enum writes a large struct over a small stack slot
  and traps. The shape is `GHOSTTY_RENDER_STATE_DATA_CURSOR_VISUAL_STYLE`, on the
  render state. Found by a crash, which is the good outcome; the silent version
  would have been the bug that passes its tests.
- **Adding `screen` to the protocol** to satisfy its six call sites. All six —
  `text(in:)`, `wordSelection`, `lineSelection`, `fullSelection`, `recentLines`,
  `selectableRowCount` — are written in terms of `line(at:)` and `totalLineCount`
  and nothing else, so the extension moved from `TerminalScreen` to
  `TerminalGridReading` and both engines get one implementation. Not one body
  changed.
- **Switching the engine on a live pane.** The setting is read once, when a pane is
  made. An engine holds the scrollback, the modes and the images, and swapping one
  out under a running shell would throw all three away mid-session. Turning the
  setting on applies to the next pane, which is the rule `terminalGPURendering`
  already follows.
- **Handing back a `GhosttyTerminalEngine` whose library failed to start.** Every
  call would be a no-op and the pane would draw nothing. `makeEngine` falls back to
  ours, and `--report-geometry` prints which one it got, so a fallback is visible
  rather than silent.
- **Reading `emulator.grid` fresh on every access.** `TerminalView` reads it about
  twenty times a frame, and for our engine each is a retain of a value type. A copy
  per access would have multiplied the per-frame cost by twenty behind an
  innocent-looking `.rows`. The snapshot is cached until the next write.
- **`render.h` for the scrollback as well.** The render state is the *viewport*; it
  has no notion of a row somebody has scrolled back to. Grid references are
  documented for exactly that — "a snapshot … meant to be read and have their
  values cached immediately" — and a scroll back into history is not a render loop.
- **Working around the tmux prompt row inside the adapter.** The adapter cannot
  tell from the outside whether a `CSI A` was counted from a park or from a clamp;
  it would have to re-implement the park rule over a grid the library owns, and
  guess. Named instead.

## Two things this item's own framing got slightly wrong

Left here rather than edited away above, because the next person reads the same
sentences.

- **"`Tests/AbydosKitTests/Fixtures/` has 0468's in-tmux and plain-pane icat
  captures."** It does not, and 0474 had already said so: the fixtures are
  `tmux-prompt.bin`, `tmux-prompt-repaint.bin` and `return-burst.bin`, and
  `IcatCaptureReplayTests` reads a path out of `ICAT_LOG`, so those captures only
  ever existed in `/tmp` on the machine 0468 was measured on. The kitty graphics
  work here is therefore tested on scripts written in the tests — a `U=1` transmit
  and placeholder cells written exactly as `icat` writes them, and a PNG built in
  the test — rather than on a capture. That is weaker evidence about `icat`
  specifically and stronger evidence about the protocol, and it is worth knowing
  which. Capturing the real thing again is still a prerequisite for closing the
  loop, and `Scripts/icat-notmux.py` in 0468's folder is the harness for the
  plain-pane half.
- **"Three are libghostty-vt's own key and mouse *encoding* APIs."** True of the
  headers and false as a plan: both encoders are built for ghostty's own app, whose
  behaviour differs from ours in ways that would be invisible until somebody hit
  them. Measured, written down under "ruled out", and their *state* used instead —
  which is the part that actually decides the bytes.

## And one thing worth saying about the whole shape

0474's recommendation was "keep going, as an option, and do not plan on deleting
our emulator", and nothing here changes that. What did change is the size of the
trade: 0474 put the saving at "at most ~2,200 lines" on the assumption that
`KittyGraphics` (1,066) and `UnicodePlaceholder` (226) both came back. Only 226 of
those do. But the other half of 0474's argument stands harder than before, because
this item found two more places where libghostty-vt's behaviour is right for
ghostty and wrong here — the key encoder, and `CURSOR_STYLE` not being the cursor
style. Every one of those is a small, findable thing; there is no reason to think
this is the last of them, and that is the tax the option was chosen to pay in
exchange for a much faster parser and reflow on resize.
