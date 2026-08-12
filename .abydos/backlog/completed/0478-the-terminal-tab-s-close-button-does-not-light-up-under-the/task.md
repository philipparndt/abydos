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

## What was done

`PanelTabStrip.closeRect(for:)` came out of `mouseDown` and sits beside
`badgeRect`. Three callers now, where there had been one and two copies of the
arithmetic: the click, the new hover, and both of the strip's drawing paths.

`hoveredClose` beside `hoveredIndex`, set in `updateHover(at:)` — which is what
`mouseMoved` now calls — and cleared in `clearHover()`, which `mouseExited`
calls. Both flags travel in one comparison, so the redraw happens when either
changes and not otherwise.

**The drawing is shared as a function, not as a tab bar.** `TabCloseButton.draw`
in `Sources/AbydosApp/TabCloseButton.swift`, beside `TabSelectionLine`, which is
the same thing for the accent line and was the precedent. It takes the rect, the
flag, the arm inset and the line width. The plate, the shape of the cross, the
cap style and the ink live there once; the two numbers stay with the callers,
because the two strips size their close boxes differently — 14 points against 12
— and the crosses come out the same size only because their insets differ to
suit. Settling either number in the shared function would have meant choosing one
strip's look for both, which is a change to the editor that this item is not
about.

Extracting a tab bar the two could share was the other answer and was not taken:
they agree on the ✕ and disagree on nearly everything else they draw — tmux's
green, the run wash, the preview control, the drop caret, the tmux window number
— so it would have been a large change for one rounded rect.

## Ruled out on the way

- **The mouse plumbing.** Nothing was missing. The tracking area already had
  `.mouseMoved`, and `mouseMoved` and `mouseExited` were both already handled.
  The only thing absent was the second question.
- **A cursor rect.** `EditorTabBar` does not set one over its close box either —
  neither file mentions `addCursorRect` or `NSCursor` — so there was no
  discrepancy to match. The pointer stays an arrow over both crosses, and making
  it something else would be a change to two strips rather than a fix to one.
- **The dirty dot has no counterpart, so nothing was swapped.** A terminal tab's
  running state is the icon's tint and a green wash over the whole tab; both are
  at the other end of the tab from the ✕ and neither competes with it. The one
  thing that *does* occupy the close box is the Claude status badge —
  `badgeRect` is literally "where the ✕ would be" — and it is only ever
  populated from `tmuxWindows`, whose items are all `isClosable: false`. The two
  cannot land on the same tab, which is what the comment there already claimed;
  it checks out, and there was nothing to do.
- **A unit test.** `AbydosKitTests` depends on `AbydosKit` alone, so no test in
  this repository can reach a view. Checked the way the rest of the app's chrome
  is: a launch option, `--tab-close-hover <path>`, which walks the window for
  every strip that can be hovered, puts the pointer on each ✕ in turn, prints
  what each strip then believes, photographs it, takes the pointer off them all
  and photographs that too. It drives `updateHover` rather than assigning the two
  flags, so it would still fail with the hit test wired to nothing — which is
  very nearly the bug that was here.
- **A real tmux server for the unclosable case.** `--run` with a `tmux
  new-session` on a socket of its own does create the session, but the mirror
  does not reach the strip inside the few seconds such a run lasts. The state is
  what matters, so `seedUnclosableTabForTesting` puts two `isClosable: false`
  items on the mirror strip the same way the panel does. The pointer sits on
  where their ✕ would be and the strip reports `close=false`.
- **`drawPillStyle` is dead** — nothing has called it since the panel's tabs
  started being drawn the editor's way, and it held a third copy of the cross.
  Left in place rather than deleted, since removing it is not this item's
  business, but it now calls the shared function, so there is one cross in that
  file instead of three.

## What the two strips looked like

`images/compare.png`, cropped from one run: each strip with the pointer on the
cross, and with the pointer gone. The editor's plate and the panel's are the same
grey at the same radius; the panel's is a touch smaller, which is its close box
being 12 points rather than 14. Neither keeps anything behind after the pointer
leaves — an inactive tab loses its cross entirely, an active one goes back to a
bare cross. tmux's strip shows neither a cross nor a plate, either way.

## Estimate

2026-08-12 07:12 — done

## Steps

- [x] `closeRect` becomes a method of the strip, asked by the click, the hover
      and the drawing alike
- [x] `hoveredClose` beside `hoveredIndex`, cleared on exit as that one is
- [x] The same highlight the editor draws, shared rather than copied
- [x] A tab that cannot be closed does not light up
- [x] Watch both strips side by side, and the pointer leaving each
- [x] Write down here what was ruled out on the way
- [x] `spec/<capability>.md` says what the project now does, if it says anything
      about tabs at all — this may be too small to have a requirement, and saying
      so is a valid answer

      No delta. `spec/` has nothing about tabs of either kind: `editor.md` is
      seven requirements about `⌘/`, and `terminal.md` is about panes, cell sizes
      and images. Nothing in either says a tab has a ✕, so there is no
      requirement for this to modify, and one hover highlight is not the place to
      start a chapter on tab chrome — the sentence it would produce ("the ✕ is
      lighter under the pointer") is a fact about a rounded rect, not a claim
      anybody would check the program against. A requirement about what a tab
      strip is for is worth writing; it is a bigger piece of work than this and
      should be written as one.
