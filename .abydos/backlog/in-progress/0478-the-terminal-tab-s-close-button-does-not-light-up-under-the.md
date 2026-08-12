# 478. The terminal tab's close button does not light up under the pointer

> small ui bug: the close button of a terminal tab does not have an hover effect
> like the close button of an editor tab

The two strips are different code, and only one of them tracks the close button.

## What each has today

`EditorTabBar` keeps **two** pieces of hover state — `hoveredIndex` and
`hoveredClose` (line 86) — updated together in `mouseMoved` (line 270) and both
cleared on exit. When the pointer is over the cross it fills a rounded rect
behind it, `NSColor.white.withAlphaComponent(0.12)`, `xRadius: 4`, inset by −1
(line 648). It also uses that same state to swap the dirty dot for the cross
(line 643), which is the second thing the terminal strip cannot do.

The strip in `BottomPanel` tracks only `hoveredIndex`. It already has the
tracking area with `.mouseMoved` (line 3615) and already handles `mouseMoved`
and `mouseExited`, so **the tracking is there and only the second question is
missing**. Its `closeRect` is computed inside `mouseDown` (line 3667) as a local,
so nothing outside the click knows where the cross is.

## The actual work

`closeRect(for:)` wants to come out of `mouseDown` and become a method the way
`EditorTabBar.closeRect(for:)` (line 237) already is, so that `mouseMoved` and
`draw` can ask the same question the click asks. Then `hoveredClose` beside
`hoveredIndex`, and the same fill in the strip's own drawing.

**Whether the two should share the drawing** is the one judgement here. They are
close enough that a copied rounded rect will drift the moment somebody changes
the colour — and far enough apart in structure that extracting a common tab bar
for one hover highlight would be a large change for a small bug. A shared
*function* that draws a close cross and its hover, taking a rect and a flag, is
probably the honest middle; say which was chosen and why.

## Worth checking while there

- **`isClosable`.** The strip's click already respects it (line 3675), so a tab
  that cannot be closed must not light up either.
- **The dirty dot.** `EditorTabBar` hides it under the pointer and shows the
  cross instead. Whether a terminal tab has an equivalent state — the running
  indicator — and whether it should behave the same way, is worth one look rather
  than an assumption.
- **The pointer's shape.** `EditorTabBar` may set a cursor rect over the close
  box; if it does and the strip does not, that is the same bug wearing a
  different coat.

## Estimate

2026-08-12 06:40 — about thirty minutes left

## Steps

- [x] `closeRect` becomes a method of the strip, asked by the click, the hover
      and the drawing alike
- [x] `hoveredClose` beside `hoveredIndex`, cleared on exit as that one is
- [x] The same highlight the editor draws, shared rather than copied
- [x] A tab that cannot be closed does not light up
- [ ] Watch both strips side by side, and the pointer leaving each
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does, if it says anything
      about tabs at all — this may be too small to have a requirement, and saying
      so is a valid answer
