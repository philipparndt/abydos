## 1. The tip

- [x] 1.1 `StyledTip`: a `Tip` value — title, detail, shortcut — and a
  borderless non-activating panel holding a drawn view, at `.popUpMenu` level,
  ignoring the mouse, added as a child of the window it hangs off.
- [x] 1.2 Drawn in the theme: the title in the text ink, the detail dimmed and
  wrapped to a readable width, the shortcut as a rounded cap at the trailing
  edge — set apart from the sentence, as the titlebar capsule sets its key
  apart, but drawn rather than dimmed.
- [x] 1.3 Shown after half a second on a control and hidden on exit, on a
  press, and when the strip leaves its window.

## 2. The strip uses it

- [x] 2.1 `PanelTabStrip.words(for:)` becomes a `Tip` per control: the pill's
  three sentences become a title, a body and ⇧⌘A.
- [x] 2.2 The AppKit tooltips for those controls go, so there is one tip and
  not two.
- [x] 2.3 `--hover-control` prints what the tip holds.

## 3. Checked

- [x] 3.1 Driven: hover each control, print the tip, and photograph the pill's.
  `--hover-control` takes a comma list, so one run says what all eight tell
  somebody; `overflow` answers "not on this strip" when no tab is hidden.
- [x] 3.2 `make test` and `make warnings`, both clean by their exit codes.
