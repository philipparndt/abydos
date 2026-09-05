## 1. One owner for the tip and the hover

- [ ] 1.1 `Sources/AbydosApp/Controls/StyledTip.swift` (or beside it) — the
  small owner a view hands its rectangles and `Tip`s to: `tip(at:)`, the show
  on a change of hovered control, the hide on exit, the rectangle in the
  view's own coordinates. The comment says why it exists: three copies of
  `PanelTabStrip`'s plumbing is where the third one starts to differ.
- [ ] 1.2 `PanelTabStrip` moved onto it, its own driven verbs
  (`hoverTrailingForTesting`, which answers lit-or-not and the tip's words
  together) green before and after — the strip is the reference this change
  spreads, so it is the thing that must not change behaviour.

## 2. The three areas

- [ ] 2.1 `ToolWindowBar` — the rail's buttons drop `toolTip` for the drawn
  tip, each naming the pane it opens and its key where it has one. The hover
  they already draw is untouched, the request having said it is right.
- [ ] 2.2 `NavigatorHeaderView` — a tracking area, a hovered-button state, the
  ground behind whichever button the pointer is on (the compact-packages
  pill's on-tint kept and the hover visible against it), and the drawn tip in
  place of the three `button.toolTip` strings.
- [ ] 2.3 `RunControl` — a hovered-rectangle state over the run, debug,
  debug-menu, scheme and status rectangles, the ground drawn under it, and the
  drawn tip replacing the `addToolTip` registrations and the tag dictionary;
  Run's ⌃R and Debug's ⌃D taken from where the menu takes them.

## 3. Proving it

- [ ] 3.1 A driven verb per area, in the shape
  `hoverStripControlForTesting` already has: a named control hovered, the
  answer saying lit or not lit and the tip's `reportForTesting` — so the words
  are checked without a screenshot.
- [ ] 3.2 A driven run over all three: every named control lit under the
  pointer and its neighbours not, the tips saying what the scenarios say, and
  a photographed frame of one hover in each area to show the ground is the
  strip's and not a second one.
- [ ] 3.3 A search for what is left: no chrome control still setting
  `NSView.toolTip`, with the rows, cells and fields that legitimately keep one
  named in the task so the grep's leftovers are explained rather than
  mysterious.

## 4. Finishing

- [ ] 4.1 `Scripts/file-size-allowed.txt` for what grew, reasons said aloud;
  `docs/release-notes-0.14.0.md` given the section.
- [ ] 4.2 `make test` and `make warnings`, both clean by their exit codes.
