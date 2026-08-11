# 474. Experiment: libghostty-vt as the terminal engine under our own terminal

> I want to use libghostty in the terminal. That way I do not have to maintain
> this myself and it already supports everything that is necessary and is very
> well tested by a wide community.

The motive is right and today is the evidence for it: 0468 was one clamped cursor
advance in our own emulator, found after two investigations and a day, and it is
exactly the class of thing an engine a thousand people use daily gets right.

This entry is the experiment, on a branch — and the shape it takes was decided
after the first draft:

> maybe we should do it like the metal renderer and make it an option first and
> keep my version for a while as well, that way I can really test it

Which is better than any table this item could have produced. **The deliverable is
a switchable engine, off by default, with the existing emulator untouched**, and
the judgement comes from weeks of real use rather than an afternoon of
measurement. The pattern is already here: `terminalGPURendering` defaults to
false, is read in one place, and the Metal path is simply not built when it is
off. The user runs with that one *on*, which is the arrangement working.

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

## The seam is the work, and the questions above are now prerequisites

An option means one protocol both engines satisfy, wide enough for what
`TerminalView`, `TmuxMirror`, `TerminalSelection` and prompt detection actually
ask. So question 3 stops being informational and becomes load-bearing, and the
seam has to be **defined from what the callers need rather than from what either
engine offers** — otherwise it comes out shaped like libghostty-vt with our own
emulator faking the difference.

Two costs to state rather than discover:

- **The existing engine must not change behaviour with the setting off.** Every
  terminal test passes through it, and those tests are why 0397 and 0468 were
  findable. If extracting a protocol forces changes to the old path, that is a
  cost of the option and belongs here.
- **Every future terminal bug now has two possible homes**, and the first question
  about any report becomes "which engine". Both of those items cost a day partly
  because nobody knew which layer to look at. `--report-geometry` exists and
  printing the engine there is nearly free.

## Deliberately not in this item

Replacing anything, or turning it on by default. If the seam turns out to be large
enough to be its own item, the boundary is the place to stop — with the answers
written down and the seam designed but not built.

## Steps

- [ ] Build and link libghostty-vt from this project, and write down exactly what
      that cost and what it puts in `Package.swift`
- [ ] Feed `tmux-prompt.bin`, `return-burst.bin` and 0468's two icat captures to
      both engines and compare, cell for cell
- [ ] Both kitty protocols — `U=1` placeholders and a `t=f` placement
- [ ] Say whether `TmuxMirror`, selection and prompt detection can be written on
      its grid API, with the specific call for each
- [ ] Throughput against `TerminalThroughputTests`, with the load stated
- [ ] Read its recent history and say how much the API has moved
- [ ] Design the seam from what the callers ask, and say what it costs the
      existing engine — nothing, if the setting is off
- [ ] The setting, in the shape `terminalGPURendering` already has: default off,
      one reader, the old path untouched
- [ ] Somebody reporting a terminal bug can tell which engine drew it
- [ ] Write down here what was ruled out on the way
- [ ] No spec change — this item changes nothing about what the project does
