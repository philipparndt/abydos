# 474. Experiment: libghostty-vt as the terminal engine under our own terminal

> I want to use libghostty in the terminal. That way I do not have to maintain
> this myself and it already supports everything that is necessary and is very
> well tested by a wide community.

The motive is right and today is the evidence for it: 0468 was one clamped cursor
advance in our own emulator, found after two investigations and a day, and it is
exactly the class of thing an engine a thousand people use daily gets right. This
entry is the experiment, on a branch, with a decision at the end rather than a
migration.

**But there are two libghostties and the difference decides everything.** The
apps on `awesome-libghostty` — conterm, Enso, fantastty, Muxy, justty, macterm —
all embed the first one. We cannot.

## libghostty (`include/ghostty.h`) — what those apps use, and why it is not for us

It is the whole terminal: it **owns the pty and the child process**, and it
renders into an `NSView` you hand it (`ghostty_surface_new`,
`ghostty_surface_draw`, `ghostty_platform_macos_s.nsview`). You give it keys and
text (`ghostty_surface_key`, `ghostty_surface_text`) and it does the rest. That is
why a terminal app can be written on top of it in a weekend.

Its own header says what it is:

> The only consumer of this API is the macOS app, and while it is fairly
> comprehensive, it is tailored to the needs of the macOS app and not designed
> for external use

and directs external users to `libghostty-vt`. Three things it does not give,
each of which this app is built on:

- **No cell-level read.** `ghostty_surface_read_selection`,
  `ghostty_surface_read_text` and `ghostty_surface_has_selection` are the whole of
  it — no cells, no rows, no scrollback, no cursor position. `TmuxMirror` (473
  lines) reads the screen. So does prompt detection, so does the `@ai_status` the
  Claude hook writes, so does our selection.
- **No kitty graphics at all** in that header. We have 1,292 lines of it
  (`KittyGraphics` plus `UnicodePlaceholder`) and two items' worth of measurement
  behind it.
- **It owns the pty.** Ours is used by far more than the terminal panel: run
  configurations, container `exec`, devcontainers, `abydos-hook`.

## libghostty-vt (`include/ghostty/vt.h`) — the one that fits

A **pure state machine**: no pty, fed bytes, keeps state. And it has the parts we
would actually be buying:

- grid traversal — `grid_ref`, `grid_ref_tracked` — over "cell codepoints, row
  wrap state, and cell styles", with scrollback, line wrapping and **reflow on
  resize**
- the OSC parser, SGR parsing, and key, mouse and focus *encoding*
- **kitty graphics**, with an example showing a PNG-decoder callback installed
  through its system interface

That is the shape this app needs: their engine underneath, our Metal renderer, our
pty, our tmux mirror, our selection, our hook. Measured against what we have, it
is a candidate to replace `TerminalEmulator` (1,616), `TerminalScreen` (421),
`KittyGraphics` (1,066), `UnicodePlaceholder` (226) and `TerminalKeys` (189) —
**3,518 of the terminal's 12,084 lines**, and by some distance the 3,518 that are
hardest to get right.

**And its own warning, which is the other half of the decision:**

> This is an incomplete, work-in-progress API. It is not yet stable and is
> definitely going to change.

So the trade is not "maintain an emulator" against "maintain nothing". It is
maintaining an emulator against maintaining a C interop layer against an API that
says it will break, in exchange for correctness we have repeatedly failed to
reach ourselves. That may well be worth it. It is not obviously worth it, and
this experiment exists to find out on evidence.

## What makes this cheap to answer honestly

**We already have the differential test.** `IcatCaptureReplayTests` replays a
captured byte stream through our emulator and counts what came out, and there are
fixtures beside it — `tmux-prompt.bin`, `tmux-prompt-repaint.bin`,
`return-burst.bin`, and 0468's plain-pane and in-tmux icat captures. Feeding the
same bytes to both engines and comparing is the experiment, and most of the
harness is written. `TerminalThroughputTests` is the same trick for speed.

## What the spike must answer, in this order

1. **Can it be built and linked at all, today, on this machine?** Zig toolchain
   or a prebuilt artifact — and note that `libghostty-spm` ships the *internal*
   `GhosttyKit.xcframework`, which is the wrong library, so this may mean building
   from source. If this step is expensive or fragile, that is itself most of the
   answer, because it lands in `Package.swift` and in every build for everybody.
2. **Does its kitty graphics cover both protocols?** 0468 established that `icat`
   speaks two: unicode placeholders with `U=1` inside tmux, and a real placement
   with `t=f` and no placeholder cells outside it. Our fixtures have both. An
   engine that handles one is not a replacement.
3. **Is the grid traversal enough for `TmuxMirror`, selection and prompt
   detection?** Codepoints, wrap state and styles is what the header promises;
   what those three actually read is the question.
4. **How fast, on our own throughput fixture, and at what load** — the honest
   comparison, and 0472 is why the load must be stated.
5. **What breaks when the API changes?** Not answerable by prediction, but
   answerable by looking: read its git history for the last few months and say how
   often and how deeply the surface has moved.

## What the deliverable became, mid-item

It was "a branch, a table of answers and a recommendation". The user changed it
to something better:

> maybe we should do it like the metal renderer and make it an option first and
> keep my version for a while as well, that way I can really test it

and then:

> I think that way we can implement the libghostty directly on main in a working
> tree, as we won't harm the existing terminal much

So the deliverable is **libghostty-vt as a switchable engine, off by default,
with `TerminalEmulator` untouched** — the shape `terminalGPURendering` already
has, where the user runs with the option *on* while the default is *off*, and
real use is the test rather than any table. The five questions stand: they are
all prerequisites, and question 3 stops being informational, because what the
callers need *is* the seam.

## Deliberately not in this item

Replacing anything, or changing what the terminal does with the setting off.

## Estimate

2026-08-11 17:52 — about 90 min; step 1 passed, building the seam

## Steps

- [x] Build and link libghostty-vt from this project, and write down exactly what
      that cost and what it puts in `Package.swift`
- [ ] Both kitty protocols — `U=1` placeholders and a `t=f` placement
- [ ] Say what selection, the render path and prompt detection would each call —
      and correct the item where it was wrong about who reads the grid
- [ ] Design the seam from what the callers need, and say whether the old path
      changes at all
- [ ] Feed `tmux-prompt.bin`, `return-burst.bin` and 0468's two icat captures to
      both engines and compare, cell for cell
- [ ] Throughput against `TerminalThroughputTests`, with the load stated
- [ ] Read its recent history and say how much the API has moved
- [ ] A setting, off by default, and one place that reads it
- [ ] Make the half-built parts refuse rather than draw something plausible, and
      name in the setting what is missing
- [ ] Say how somebody reporting a terminal bug will know which engine drew it
- [ ] Write the recommendation, with the cost of being wrong in each direction
- [ ] Write down here what was ruled out on the way
- [ ] No spec change — this item changes nothing about what the project does

## 1. Can it be built and linked? Yes, and it cost 62 seconds

This was the stop condition, and it passed far more easily than the item feared.

**There is a build target for exactly this.** `zig build -Demit-lib-vt=true
-Doptimize=ReleaseFast` in a ghostty checkout. `-Demit-lib-vt` is a first-class
option (`src/build/Config.zig:80`) which turns off the macOS app, the internal
xcframework and the docs, and builds vt.h's library alone. It is not a hack or a
private target: ghostty means for this to be built on its own, and
`GhosttyDist.zig` even has a separate source manifest for it.

| | |
|---|---|
| zig needed | 0.16.0 — and `build.zig.zon` says `minimum_zig_version = "0.16.0"`, which is **exactly** what `brew install zig` gives today |
| clone | `--filter=blob:none`, about 20 s |
| build | **62 s wall**, 176 s CPU, from cold, no errors |
| cache left behind | 350 MB in the checkout, 248 MB in `~/.cache/zig` |
| what it emits | `libghostty-vt.a` (8.4 MB arm64), a dylib, **and a universal `ghostty-vt.xcframework`** carrying a `module.modulemap` |
| link needs | `-lc++` and nothing else — simdutf and highway are C++ but sit *inside* the archive, and not one symbol is left unresolved |
| exported symbols | 192 `ghostty_*` |

**It ships a `module.modulemap` naming the module `GhosttyVt`**, so Swift imports
it with no shim, no bridging header, no `unsafeFlags`:

    .binaryTarget(name: "GhosttyVt", path: "Vendor/ghostty-vt.xcframework")

plus `linkerSettings: [.linkedLibrary("c++")]` on `AbydosKit`. That is the whole
manifest change — two lines and a dependency entry. `xcrun swift build --target
AbydosKit` then compiles Swift calling `ghostty_terminal_new`,
`ghostty_terminal_vt_write` and `ghostty_terminal_get`, and the equivalent C
program prints the grid back:

    size = 80x24
    row 0: |hello world|
    row 2: |    placed|
    row0 wrap=0 kittyPlaceholder=0 dirty=1

### What it puts in the repository, and what that costs everybody

`Scripts/build-libghostty-vt.sh` pins the ghostty commit (**426386b85**) and
rebuilds the artifact from it; `Vendor/ghostty-vt.xcframework` is the artifact —
**18 MB, committed, macOS-only** (the build also emits iOS slices, another 17 MB
this app can never load, which the script drops).

Committing a binary needs a reason, and the reason is that **there is nothing to
depend on**. libghostty-vt has no release, no tag, no Swift package and no
published artifact; its version string is `0.1.0-dev` and `git tag | grep -i vt`
is empty. `libghostty-spm` ships `GhosttyKit.xcframework`, which is the *other*
library and the wrong one. So the choice is a committed artifact, or every clone
and every CI run needing zig plus 62 seconds plus 350 MB of cache. The artifact
is much the cheaper for everybody who is not changing it.

The costs, stated because they are not zero:

- **18 MB in git**, and again on each rebuild of the artifact.
- **Every build links it, with the setting on or off.** SPM linkage is a
  build-time fact and a runtime setting cannot undo it. A compile-time flag would
  avoid that but would also mean the user could not switch the engine on in the
  app they actually use, which is the whole point of the option.
- **Upgrading is a deliberate act, not a version bump.** There is no version to
  bump, and the header says of itself that it "is definitely going to change".
- `brew install zig` giving exactly 0.16.0 is luck, and it will not hold. When
  ghostty's minimum moves past Homebrew's zig, rebuilding the artifact means
  fetching a matching zig by hand. It does not affect anybody who only *builds
  this app* — that is the point of committing the artifact — but it is a cost on
  whoever next updates it.

## 2. Kitty graphics: it covers one of `icat`'s two protocols, not both

**This is the clearest "no" in the item, and it is the answer to the question
0468 taught us to ask.** 0468 established that `icat` speaks two protocols and
that which one depends on tmux. libghostty-vt covers one of them.

### `t=f` real placement, outside tmux — fully covered

Everything 0468 needed is there, including the part our own emulator got wrong:

- enumeration: `ghostty_kitty_graphics_placement_iterator_new` /
  `_placement_next` / `_placement_get`, giving `IMAGE_ID`, `X_OFFSET`,
  `Y_OFFSET`, `SOURCE_*`, `COLUMNS`, `ROWS`, `Z`
- position: `ghostty_kitty_graphics_placement_viewport_pos`, which explicitly
  reports a negative row when the placement has scrolled above the viewport
- **the footprint from pixels**: `ghostty_kitty_graphics_placement_grid_size` —
  "if the placement specifies explicit columns and rows, those are returned
  directly; **otherwise they are calculated from the pixel size and cell
  dimensions**". That is exactly the `s=732,v=988` with no `c=`/`r=` case 0468
  measured, done by the library.
- one call for a whole frame's worth: `_placement_render_info`
- image bytes ready to upload: always decoded and always uncompressed, with a
  monotonic `GENERATION` per image and per store, which is a better cache key
  than the size heuristics we use.

### `U=1` unicode placeholders, inside tmux — half covered, and the half we need is missing

The escape is honoured, the image is stored, and the virtual placement is
enumerable (`GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL`). There is even a
fast row flag, `GHOSTTY_ROW_DATA_KITTY_VIRTUAL_PLACEHOLDER`, which is the same
prefilter ghostty's own renderer uses.

**But the part that turns placeholder cells into picture fragments is not
exported, and the geometry calls actively refuse virtual placements.**
`placement_rect` and `placement_viewport_pos` both document returning
`GHOSTTY_NO_VALUE` for a virtual placement, and `render_info`'s
`viewport_visible` is documented false "when the placement is fully off-screen
**or virtual**". Searching the whole of `include/ghostty` finds no `0x10EEEE`, no
diacritic table, no placeholder iterator and no function with "placeholder" in
its name other than that row flag.

ghostty *has* this code — `src/terminal/kitty/graphics_unicode.zig`, 1,361 lines,
including a 297-entry sorted diacritic table, the run-coalescing iterator, the
fg-colour-to-image-id decoding and the aspect-preserving fragment maths. Its only
consumer is `src/renderer/image.zig`, which is ghostty's own GUI renderer, and
`src/lib_vt.zig` exports 16 `ghostty_kitty_graphics_*` functions of which none
touch it.

So **`UnicodePlaceholder` (226 lines) is not replaceable at all**, and
`KittyGraphics` (1,066) is only partly. Both stay ours whatever happens. That
takes the "3,518 lines we could stop maintaining" down by 1,292 before anything
else is decided — and it removes the tmux path, which is the one the user
actually runs.

### Two ways to get nothing and think the library is broken

Written down because both are silent, and both would have cost an afternoon:

- **Graphics is off until a non-zero storage limit is set**
  (`GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT`), and the file media are off
  by default too (`image_limits = .direct`). A forgotten limit is
  indistinguishable from "this terminal has no graphics" — the library does not
  even answer `a=q` in that state, deliberately.
- **Query responses are not encoded at all unless a `WRITE_PTY` callback is
  installed.** Outside tmux `icat` asks three questions and waits for answers, so
  with no callback it *hangs* rather than misdraws. `GhosttyTerminalEngine`
  installs both in `init` so this is not the missing piece later.

Also: animation (`a=f`, `a=a`, `a=c`) is explicitly unimplemented and returns
"ERROR: unimplemented action". Irrelevant to `icat`, but it is the one thing in
this area the library says it does not do.

## 3. What the callers would call — and two premises in this item were wrong

The item said "`TmuxMirror` (473 lines), selection and prompt detection". Reading
the call sites rather than the file names says otherwise, and it makes the seam
much narrower than feared:

- **`TmuxMirror` does not touch the emulator at all.** Not one reference to
  `TerminalEmulator`, `TerminalScreen`, `TerminalLine` or `TerminalCell` in all
  473 lines. It is a `tmux(1)` subprocess wrapper — `list-windows`,
  `list-clients`, `set-option`, `paste-buffer` — and `@ai_status` is a tmux
  *window option* read with a format string, not anything on screen. **It is
  unaffected by the engine.** The item's claim that it "reads the screen" is
  simply not true of today's code.
- **There is no prompt detection.** No OSC 133, no semantic marks, no
  `promptRow`, and no OSC 7 — `TerminalDirectory` says in its own comment why it
  asks the pty and `pgrep` instead. So there is nothing to put behind the seam
  and nothing to port. (Worth knowing for later: libghostty-vt would hand this
  over for free if we ever wanted it, via
  `GHOSTTY_ROW_DATA_SEMANTIC_PROMPT` per row.)

So the grid is read by two things: **selection** and **the render path**.

| Caller | What it reads | The libghostty-vt call |
|---|---|---|
| `TerminalSelection` | absolute `line(at:)`, `totalLineCount`, and per cell `scalar`, `combining`, `isWideTrailer`, column count. Nothing else — no attributes, no cursor | `ghostty_terminal_grid_ref` with `GHOSTTY_POINT_TAG_SCREEN` → `ghostty_grid_ref_cell` → `ghostty_cell_get(CODEPOINT/WIDE)` and `ghostty_grid_ref_graphemes`. Selection *anchors* would be better as `ghostty_terminal_grid_ref_track`, which the header says "follows its cell across … scrolling, scrollback pruning, resize/reflow" — that is strictly better than our `realignSelectionForDiscardedLines` |
| Render path (`TerminalView`, `TerminalMetalRenderer`) | per frame, a band of rows: `scalar`, `combining`, `isWideTrailer`, `attributes.resolved`, `bold`/`dim`/`italic`/`hidden`/`underline`/`strikethrough`, `link` | **not `grid_ref`.** Its own docs: "The grid reference APIs are **not** meant to be used as the core of a render loop. They are not built to sustain the framerates needed for rendering large screens. Use the render state API for that." So `render.h`: `ghostty_render_state_new`, `_update` (or `_begin_update`/`_end_update` to hold the terminal lock briefly), `_row_iterator_new`/`_next`, `_row_cells_new`/`_next`/`_get_multi` for `RAW`/`STYLE`/`GRAPHEMES_BUF`/`BG_COLOR` |
| Hyperlinks | `attributes.link` → `emulator.link(for:)` | `ghostty_grid_ref_hyperlink_uri`, which returns the URI itself rather than an index — so our `UInt16` link table would become a cache on our side |
| Cursor, size, modes | `cursorRow`, `cursorColumn`, `isCursorVisible`, `isAlternateScreen`, `title`, `totalLineCount`, `scrollback.count` | `ghostty_terminal_get_multi` with `CURSOR_X`, `CURSOR_Y`, `CURSOR_VISIBLE`, `ACTIVE_SCREEN`, `TITLE`, `TOTAL_ROWS`, `SCROLLBACK_ROWS` — one call for all of them, which is what `_get_multi` exists for |

**The one thing genuinely missing: `discardedLineCount`.** Ours counts the lines
that have fallen off the top for good, and the scrollbar and selection realignment
use it to tell an absolute index from an older frame apart from a current one.
libghostty-vt prunes its own scrollback (by *bytes*, not lines) and does not
report how many it threw away. The workaround is a tracked grid reference pinned
to the oldest line, which reports no value once that line is gone — real, but it
is bookkeeping we would be adding rather than removing.

Everything else that looked like it might be a problem is not: `GlyphAtlas`,
`Ligatures` and `ShapedRuns` never see an engine type at all — they are keyed on
`UInt32` scalars — so they work unchanged under either engine.

## The seam, and why the old path did not have to change

`Sources/AbydosKit/Terminal/TerminalEngine.swift`, and **no file of the old
engine was edited to make it fit.** `TerminalEmulator` conforms in an extension
with one line of body (`var grid: TerminalGridReading { screen }`) and
`TerminalScreen` with one (`var scrollbackCount: Int { scrollback.count }`). Both
extensions are in the new file.

That was luck earned earlier rather than luck: **the render path already treated
the screen as a snapshot.** `TerminalView` does `let screen = emulator.screen`
and then walks the copy, because `TerminalScreen` is a `Sendable` value type. So
"a grid that keeps the frame it was given" — which is the one hard requirement,
since libghostty-vt's untracked grid references are explicitly "only valid until
the next update to the terminal instance" — was already how the caller worked.

Being pedantic about "untouched", because that claim is what makes landing on
main safe:

- `git show --stat` for the seam commit touches no file under
  `Sources/AbydosKit/Terminal/` that existed before, except by adding two new
  ones.
- No signature changed, no access level changed, no order of operations changed.
- With the setting off, the bytes take the identical path through the identical
  code. `TerminalEmulator` does not know the protocol exists at runtime.
- The 2,410-test suite is still testing the engine it was written for, which
  matters because those tests are why 0397, 0404 and 0468 were findable.

### What is *not* wired, and why it stopped there

**The setting does not yet switch the engine in `TerminalView`.** It is
registered, off by default, shown in the settings window, and reported by
`--report-geometry` as `engine=libghostty-vt(requested,not-wired)` when it is on
— so it cannot silently look like it is working.

The reason to stop there rather than push on: `TerminalView` reads the emulator
at about ninety call sites, and roughly forty of the members it uses are not on
the seam yet — `graphics`, `link(for:)`, `encodeMouse`, `encodeArrow`,
`encodeModifiedKey`, `mouseTracking`, `bracketedPaste`, `keyboardFlags`,
`reportsFocus`, `cursorShape`, `onBell`, `onClipboardWrite`, `onOpenFile`,
`colourLookup`. Widening the protocol to all of them and changing
`let emulator: TerminalEmulator` to the protocol is a real change to a
3,019-line view, and doing it in a hurry is exactly how the old path stops being
untouched. That is the next stage, and it is worth its own commit rather than
being buried in this one.

The temptation to resist, written down so nobody reaches for it: feeding both
engines the same bytes and taking the *grid* from libghostty-vt while graphics,
modes and encoding stay with ours. It would appear to work and would be wrong —
placements computed by one engine over a grid produced by the other is precisely
the "silently misrenders" failure that makes a half-built option worse than none.

## 5. How much the API has moved: 9% of commits break something, and shallowly

Measured off the git history of `include/ghostty/vt.h` and `include/ghostty/vt/`.

**Age.** The umbrella header is 10.5 months old (2025-09-24), but the part that
matters is much younger: `terminal.h` began 2026-03-13, and 22 of the 34 current
headers were created in the last five months. `snapshot.h` and `io.h` are eight
days old.

**Rate.** 16 commits touched those headers in the last month, 62 in three, 171 in
six — about four a week, with 89% of all header commits inside the last six
months. This is under active construction, not settling.

**Shape of the churn.** Overwhelmingly additive. Over three months: +4,010 /
−374 lines, and most removals are rewritten doc comments. Public function count
went 145 → 202 in three months with **2 removed and 2 signatures changed**. Enum
constants: **+104 added, 0 removed, 0 renumbered**, every enum carrying an
explicit `*_MAX_VALUE` sentinel.

**Breaks.** Of 66 header commits in four months, **6 (9%) are source-breaking**:

| Commit | What broke |
|---|---|
| `03d5fa268` (07-27) | `ghostty_terminal_new` lost its `GhosttyTerminalOptions` struct and became positional `cols, rows`. **Hits every consumer.** |
| `cfc19e805` (08-05) | `ghostty_terminal_mode_get/set` deleted; migrate to `terminal_set/get` with `GHOSTTY_TERMINAL_OPT_MODE`. Deepest recent one — a call-shape change |
| `20a1bfa5f` (07-08) | four colour functions went value → pointer. Mechanical |
| `634ef7198` (07-10) | clipboard callback signature changed, 7 days after being added |
| `847b8afc8` (05-23) | `selection_validate` removed the same day it was added |
| `2c1dad790` (04-11) | kitty graphics info structs replaced by enum-tag getters |

**Where the risk is, and it is not evenly spread.** `terminal.h` is the single
volatile file — 28 commits in three months, and every recent break is in it.
`screen.h` has had **zero** commits in three months. `grid_ref.h` is unchanged
since May. `render.h` is +122/−0, purely additive. Of the 40 declarations that
existed six months ago, **39 are byte-identical today**. So stability tracks the
area almost perfectly, and the areas the render path and selection need are the
stable ones.

**Two mitigations that are measurably worth having**, both already applied in
`GhosttyTerminalEngine`:

- **Include only `<ghostty/vt.h>`, never a sub-header.** Two of the apparent
  breaks were declarations moving between sub-headers with names and signatures
  untouched; the umbrella makes both non-events.
- **Wrap construction and option setup in one place.** Three of the six breaks
  landed on `terminal_new` and the option/callback surface.

**Expected cost.** Upgrading monthly, a compile break about one month in two;
quarterly, near certainty. Median fix under ten lines; the two expensive ones
were a couple of hours. And no version to pin to except a commit hash, because
there is still no tag: the README says "the API signatures are still in flux" and
"we haven't tagged libghostty with a version yet", with no semver policy and no
changelog.
