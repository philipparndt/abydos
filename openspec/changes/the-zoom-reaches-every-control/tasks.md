## 1. The arithmetic, tested without a window

- [x] 1.1 Add `ControlMetrics` to AbydosKit: the height, the horizontal padding and the corner radius of a drawn control, from a design-time font size and a scale, with the measured line height given in rather than assumed.
- [x] 1.2 Add `CommitRowMetrics` to AbydosKit: a commit row's height from the two measured line heights and the paddings, so the row is derived rather than the constant 40 it was.
- [x] 1.3 Tests beside `PanelRowSnapTests` over all nine zoom steps: a control's height at 2.0 is twice its height at 1.0 within rounding, and a commit row is never shorter than the content it is given.

## 2. The library

- [x] 2.1 Create `Sources/AbydosApp/Controls/` and move `DrawnButton` into it unchanged, keeping its two callers working.
- [x] 2.2 Add `ScaledControls`, the registry: weak boxes, one `.abydosSettingsChanged` observer, a `reapply()` walk that drops empty boxes, and a count the driver can read.
- [x] 2.3 Generalise `DrawnButton` into the library's drawn push button and glyph button, taking their metrics from `ControlMetrics` and registering on init.
- [x] 2.4 Add the drawn checkbox. Compare it against a 1× capture of the system's; if it cannot be made to read as a checkbox, stop, leave `Hide read` and `Whole file` bezelled, and say so here rather than dropping it quietly.
- [x] 2.5 Add the choice control. Try drawn first; if the arrow-key behaviour between segments cannot be kept, keep `NSSegmentedControl` and make it a *measured* member, which the design allows.
- [x] 2.6 Add the measured search field: AppKit's field, given `Theme.uiFont` and a scaled height constraint, both re-taken on a scale change.

## 3. The log page

- [ ] 3.1 Move the search field and the scope control onto the library.
- [ ] 3.2 Re-take the commit table's and the file table's row heights on a scale change, from `CommitRowMetrics`, and re-lay-out the rows rather than leaving the height read at build time.
- [ ] 3.3 Driven: capture the log page at 1.0 and at 2.0 and show the whole of the short hash inside the row at both, which is the report.

## 4. The commit page

- [ ] 4.1 Move `Stage`, `Unstage`, the `…` verb, `Draft`, `Commit`, `Push`, the message-history control and the `Amend` checkbox onto the library.
- [ ] 4.2 Move the description chevron onto the library's glyph button.
- [ ] 4.3 Read `PanelRowSnap` before writing anything for the detail area, and settle the design's open question: either the existing machinery covers this split or it does not. Recompute the division on a scale change, by whichever answer that is.
- [ ] 4.4 Driven: toggle presentation mode with the commit page open and show the detail area at the working size afterwards.

## 5. The pull-request pages

- [ ] 5.1 Move the review page's header — the review and check-out verbs, the two switches, the view-mode control — onto the library.
- [ ] 5.2 Move the list's scope control and the glyph beside it onto the library.
- [ ] 5.3 Driven: capture both at two scales.

## 6. The project tree's palette

- [ ] 6.1 Re-apply the outline view's background and the container's colour in `ProjectNavigatorViewController.applySettings()`, beside the row height and the indentation that are already re-applied there.
- [ ] 6.2 Give the navigator's container the `colourSource` closure its sibling containers in `MainWindowController+Layout` already have.
- [ ] 6.3 Driven: switch the palette with the tree showing and capture it, which is the screenshot that was reported — one pane, half light and half dark.

## 7. Finishing

- [ ] 7.1 Note in the design what was found out about why `ThemeSwap` did not reach the outline view, or that it was not chased and why.
- [ ] 7.2 Check `Scripts/file-size-allowed.txt` for any file this pushed over its aim.
- [ ] 7.3 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the five delta specs in this
change are what it makes true.
