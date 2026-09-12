## 1. The fields and labels

- [x] 1.1 `StructurePane`: `ScaledSearchField` for the filter, `ScaledLabel`
      for the placeholder, a `ScaledHeights` for the outline; `applyThemeChange`
      removed, having no caller.
- [x] 1.2 `ScratchesPane`: `ScaledSearchField` for the search, `ScaledLabel`
      for the empty label, a `ScaledHeights` for the table.
- [x] 1.3 `PullRequestsPane`: the trouble text a `ScaledLabel`.

## 2. The switches

- [x] 2.1 `BacklogPane`: *List / Board* and *Backlog / OpenSpec* as
      `DrawnChoice`, *Refresh* as a `DrawnButton` the pane holds; the font
      lines for them leave `applySettings`.

## 3. Proving it

- [x] 3.1 The zoom report over each of the four panes at 1.0 and 2.0,
      recorded in the design.

## 4. Before finishing

- [x] 4.1 The release note from the design, in the notes for the next version.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.
