## Why

**Blame is where nobody looks for it, and a click on it goes nowhere.** The
column exists — View ▸ Editor ▸ Toggle Blame, ⌥⌘B, and *Show Blame* on the
editor's gutter menu — and a colleague could not find it: JetBrains puts
*Annotate with Git Blame* on the file's context menu and VS Code with GitLens
puts *Toggle File Blame* on the tab and in the palette by name, and the tree
and the tab are where a question about a file is asked. Once found, clicking
a name posts a toast with the commit's summary, hash, author and time, and
then the toast goes away; the commit itself, its diff and the file as it was
then are a page in this app and the click does not reach them.

And the column lies about moved code. It runs plain `git blame`: a block
moved within a file is blamed on whoever moved it, and a repository with a
`.git-blame-ignore-revs` for its formatting commit blames every line on that
commit — which GitHub's blame view and both IDEs honour and this one does
not. No spec describes any of it; blame is the one editor feature with no
requirement written down.

Asked for on 2026-09-07: "what could be missing for git blame? A colleague
told me that he is missing it … maybe a context menu on the file for git
blame?"

No originating backlog item: asked for directly.

## What Changes

- **Blame on the file's context menu** in the project tree and on the tab's
  menu, as *Blame*, which opens the file if it is not open and turns the
  column on; through the menus it is in the palette by name. The gutter's
  *Show Blame* and ⌥⌘B stay.
- **A click on a blame entry lands on the commit**: the log page scoped to
  the file, at that commit, with the commit's row selected so its message
  and its diff of the file are on screen. An uncommitted line says so in a
  toast, since there is no commit to go to.
- **Moves and copies are followed** with `-M -C`, so a moved block keeps
  its author, and **`.git-blame-ignore-revs` is honoured** when the
  repository has one at its root, so a formatting commit does not own every
  line. A `blame.ignoreRevsFile` git config is git's own and keeps working.
- **A spec for blame**, finally: what the column shows, where it is turned
  on, what a click does, what git is asked.
- **Not proposed:** blaming the revision before the clicked commit, inline
  blame for the caret's line, a hover, age colouring, and history for a
  selection — a second change once this one has been used.

## Capabilities

### New Capabilities

- `git-blame`: the column, the three doors to it, the click landing on the
  commit, moves and ignored revisions.

### Modified Capabilities

<!-- None. `git-log-page-tree` is not changed: the page is opened scoped, as
it already can be. -->

## Impact

- `Sources/AbydosKit/Git/GitBlame.swift` — the arguments: `-M -C`, and
  `--ignore-revs-file` when the file is there; `arguments(for:in:)` split
  out so a test can read them.
- `Tests/AbydosKitTests/GitBlameTests.swift` — a moved block keeping its
  author, and an ignored formatting commit not owning the line, over a
  repository the test makes.
- `Sources/AbydosApp/Navigator/ProjectNavigatorViewController.swift` and
  `Editor/EditorTabBar.swift` — the *Blame* items and their callbacks.
- `Sources/AbydosApp/MainWindowController+Layout.swift` — the wiring: open,
  then blame; and the click through to the log page scoped and selected.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — `showBlame()`
  beside `toggleBlame()`, and the click's callback carrying the commit and
  the file rather than posting a toast.
- `Sources/AbydosApp/Git/HistoryPane.swift` — selecting the first row from
  outside a test.
