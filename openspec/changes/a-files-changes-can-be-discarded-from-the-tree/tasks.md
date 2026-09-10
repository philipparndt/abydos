## 1. The verb, shared

- [ ] 1.1 `MainWindowController.discard(paths:subject:)`: the insurance, the
      discard across owners and the toast, lifted from `performDiscard`; the
      pane's `performDiscard` calls it and keeps its selection bookkeeping.
- [ ] 1.2 The estate from the window, not the pane, so the tree can ask with the
      pane closed.

## 2. The menu

- [ ] 2.1 *Discard Changes* in `ProjectNavigator+Menu.swift` after *Add to
      .gitignore…*, its title from `GitDiscard.menuTitle` for the selected rows.
- [ ] 2.2 `menuNeedsUpdate`: hidden unless a selected row's status — a folder's
      aggregate — is neither unmodified nor ignored, and hidden over a conflict.
- [ ] 2.3 The action: `discardable` for the tree's rows — paths, the changes
      under them, the subject — the `GitDiscard` alert, and the shared verb on
      the destructive button.

## 3. Proving it

- [ ] 3.1 Tree steps `discard` (prints title and question, discards nothing)
      and `discard-confirm` (discards on the scratch copy, prints the file's
      porcelain status).
- [ ] 3.2 Driven on a scratch checkout: a modified file, a folder with two
      modified and one untracked, an unmodified file (absent), a conflict
      (absent), and the modified file open in a tab, its text read back after.
      Recorded in the design.

## 4. Before finishing

- [ ] 4.1 Say it in the release notes: the paragraph is in the design.
- [ ] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `project-view` is what this
change adds to.
