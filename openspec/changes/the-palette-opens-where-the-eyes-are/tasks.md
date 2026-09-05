## 1. One show, two placements

- [ ] 1.1 `ProjectSwitcherPopover.show` takes where it is to appear — anchored
  to a view, or centred over a window — and builds the same
  `SwitcherViewController` either way. The comment says why both exist: a
  click's list belongs at the control, a key's belongs where the eyes are.
- [ ] 1.2 The centred path uses `PalettePanel` with the placement
  `RunningSessionsPalette.place` has (centred horizontally on the parent, 120
  points down from its top, kept inside the parent's frame), shared rather
  than copied — one arithmetic, so the two palettes cannot drift.
- [ ] 1.3 Escape, resign-key and ⇧⌘P pressed again close it, the last caught
  on the panel as ⇧⌘A's is, because a child window's responder chain does not
  run through its parent.

## 2. The callers

- [ ] 2.1 `AppDelegate`'s ⇧⌘P item asks for the centred placement; the project
  pill, the branch pill and the run control keep the anchored one, and are
  read to confirm nothing else calls `show`.

## 3. Proving it

- [ ] 3.1 A `placementForTesting` for the switcher's panel in the shape
  `RunningSessionsPalette` already prints — size, centred yes/no, distance
  from the parent's top — so a driven run checks the geometry without a
  screenshot.
- [ ] 3.2 A driven run: ⇧⌘P opening centred over a wide window and over a
  narrow one, the rows the same as the pill's, Escape and a second ⇧⌘P
  closing it, and a click on the pill still opening at the pill. One
  photographed frame of each, since placement is the subject.

## 4. Finishing

- [ ] 4.1 `docs/release-notes-0.14.0.md` given the paragraph, and
  `Scripts/file-size-allowed.txt` raised if anything grew past its line.
- [ ] 4.2 `make test` and `make warnings`, both clean by their exit codes.
