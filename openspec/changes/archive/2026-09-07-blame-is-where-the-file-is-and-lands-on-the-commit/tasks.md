## 1. What git is asked

- [x] 1.1 `GitBlame.arguments(for:in:)` — `blame --line-porcelain -M -C`,
  plus `--ignore-revs-file .git-blame-ignore-revs` when that file is at the
  root; `lines(for:in:)` runs them.
- [x] 1.2 `GitBlameTests` over a repository the test makes: a block moved by
  a second author keeping the first; a re-indenting commit listed in the
  ignore file not owning the lines; the arguments with and without the file.

## 2. The doors

- [x] 2.1 `EditorViewController.showBlame()` beside `toggleBlame()`: on if
  it is not, and nothing if it is.
- [x] 2.2 *Blame* on the tree's file row and on the tab's menu, each a
  callback carrying the URL; `MainWindowController` opens the file pinned
  and calls `showBlame()`. Hidden on folders and non-file rows.

- [x] 2.3 A right-click anywhere in the gutter opens the gutter's menu;
  `gutterMenu(at:)` is the one decision, the breakpoint's menu first where
  there is a marker, and the caret stays put.

## 3. The click

- [x] 3.1 `CodeView.onShowBlameDetail` becomes `onRevealCommit`; the group
  passes the entry and the file up; the window opens the log page scoped to
  the commit's hash, narrows it to the file, and selects the first row.
  `HistoryPane.selectFirstCommit()` for the last step. An uncommitted entry
  keeps a toast that says so.

- [x] 3.3 `GitBlame.Line.path` from the porcelain's `filename`, and the
  click scopes the log page to it — a file archived or renamed since the
  commit came up as an empty log.
- [x] 3.2 The pointer over an entry lights the commit's run and shows the
  pointing hand; a rest shows a `StyledTip` with the summary, author, date
  and hash and the sentence that a click opens the commit in the log. An
  uncommitted entry's tip says there is no commit to go to.

## 4. Proving it

- [x] 4.1 The tree driver reports *Blame* in `menu` and gains `blame`; the
  editor-menu driver gains `blame-click:<line>` and the report says which
  page opened and which row is selected.
- [x] 4.2 Driven over a scratch repository with two authors and a moved
  block: *Blame* from the tree opening the file with the column on; the
  moved block's author; the click landing on the log page with the commit's
  row selected; the ignore file taking the formatting commit out.

  Recorded 2026-09-07 over `blame-demo` (Ada wrote the values, Grace moved
  the block down, a third author re-indented, and the re-indent is named in
  `.git-blame-ignore-revs`):

      TREE menu: … Open | Open Externally | Blame | Open as Hex | …
      TREE blame: main.swift
      EDITOR-MENU blame: visible=true authors=Ada,Ada,Grace,Grace,Ada,Ada,Ada,Ada
      EDITOR-MENU blame-click 6: a48035ed Ada
      EDITOR-MENU pages: main.swift, Log · a48035ed0fe0…
      LOG-PAGE: layout=page scope=main.swift commits=1
        a48035e no graph Ada the values
      files=1  main.swift
      PALETTE 1 commands
        View › Editor › Toggle Blame  [⌥⌘B]

  The hover, the right-click, and the click after the file was moved to
  `src/main.swift` in a later commit, recorded the same evening:

      EDITOR-MENU gutter-right 3: Show Blame        (column off)
      EDITOR-MENU gutter-right 3: Hide Blame        (column on)
      EDITOR-MENU blame-hover 6: lit 5–8 · title=[the values] detail=[Ada · … · a48035ed. Click to open the commit in the log, scoped to this file.]
      EDITOR-MENU blame-click 6: a48035ed Ada
      LOG-PAGE: scope=main.swift commits=1 · a48035e Ada the values

  The scope is the path the line had at that commit, not today's, which is
  why the page is not empty.

  The moved block (lines 5–8) stays Ada's; the re-indent owns no line. The
  palette query has to land after the window is key: a run under load saw
  `0 commands` at the driver's 2.5 s and `1 commands` on the next two runs.

- [x] 4.3 `blame-hover:<line>` on the editor-menu driver says which lines
  lit and what the tip says; driven with a screenshot of the tip.

- [x] 4.4 `gutter-right:<line>` on the editor-menu driver says what a
  right-click at the gutter's left edge opens.

## 5. Finishing

- [x] 5.1 `Scripts/file-size-allowed.txt` raised by what the doors added and
  no more.
- [x] 5.2 Release notes section for the next version.
- [x] 5.3 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [x] 5.4 `make test` and `make warnings`, both clean by their exit codes,
  with the run's load said: 4283 tests passed in 47 s at a load of 4–11
  (2026-09-07 20:37, after the hover, the right-click and the path scope);
  `make warnings` exited 0 in the same run.
