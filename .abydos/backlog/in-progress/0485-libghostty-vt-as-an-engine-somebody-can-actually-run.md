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

## Steps

- [ ] Try our placeholder layer on libghostty-vt's grid and placement store, and
      say early whether the tmux image path can work without an upstream export
- [ ] The sixteen missing members, with `screen`'s six call sites moved to `grid`
- [ ] `TerminalView` holds a `TerminalEngine`, chosen by the setting
- [ ] The render path off `grid_ref` and on to `render.h`
- [ ] The snapshot costs the visible rows rather than the scrollback
- [ ] An answer for `discardedLineCount`, or a reason it is not needed
- [ ] Every terminal test that can run against both engines does, and the list of
      those that cannot is written here with why
- [ ] 0404's three escapes: fixed, or reported upstream and named in
      `unimplemented`
- [ ] `unimplemented` is empty, or every entry in it refuses rather than guesses
- [ ] Write down here what was ruled out on the way
- [ ] `spec/terminal.md` says what the project now does
