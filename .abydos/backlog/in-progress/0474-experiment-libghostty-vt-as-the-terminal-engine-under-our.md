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

2026-08-11 17:41 — about two hours left; step 1 is a from-source zig build

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
