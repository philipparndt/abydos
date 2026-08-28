## Why

A window asked to follow its terminal follows it into a git checkout and nowhere
else. `cd` into an SVN working copy, or into any folder with no source control at
all, and nothing happens: no movement, no explanation, and no way to tell the
refusal from the feature being broken. Reported directly — "for folders with e.g.
SVN content, or no source control at all it does not sync", against a build where
following between checkouts works well.

The refusal is one line. `ProjectRoot.find(from:)` climbs looking only for `.git`
and returns nil at the filesystem root; `projectToFollow` aborts on that nil, so
`terminalDirectoryChanged` returns without doing anything. Everything above it is
already indifferent to what kind of directory it is holding: `TerminalDirectory`
reads the pty's foreground working directory through `proc_pidinfo`, asks the
tmux server when tmux is in front, and `BottomPanel.reportWorkingDirectory()`
hands on whatever path comes back.

There is no originating backlog item. The rule being replaced was written down
deliberately, and two items paid for the reasoning around it: 0509, where a
project opened at a subdirectory of a checkout threw itself away for the checkout
about a second after it was opened, taking the tabs somebody had just opened;
and 0534, where a driven run followed a shell whose working directory had been
deleted underneath it into `~/.config/zshutil`. Both are cited below, because
both constrain what the replacement is allowed to be.

## What Changes

- A working copy is recognised by `.svn` and `.hg` as well as `.git`, so an SVN
  or Mercurial checkout is a project and is followed exactly as a git one is.
  `.abydos`/`.ideai` counts too: it is this app's own record that somebody
  deliberately opened this folder as a project.
- **A folder in no working copy at all is shown, and is not a project.** The
  window points its tree, its search and its file index at it; there is no
  branch, no run configuration, no session of its own, and nothing is written
  into the folder.
- Moving between two such folders re-points the tree and **leaves every open file
  open**. Nothing is captured, written or restored, because there is nothing
  per-folder to capture.
- Such folders share **one global session**, holding files and not terminals,
  read and written on the way into and out of them. The existing `URL?` "nil
  means global" convention, which `OpenScratches` and `ScratchLibrary` already
  use for scratches.
- A folder in no working copy is not recorded in Recent Projects, so walking
  through directories does not fill the switcher.
- **BREAKING** for the spec only: `openspec/specs/terminal` currently requires
  that "a directory belonging to no repository at all leaves the window where it
  is". That sentence, its scenario, and the test asserting it all invert. No
  public API changes and nothing a user has configured behaves differently
  while following is switched off.
- Unchanged, deliberately: a driven run still follows its terminal nowhere; a
  directory inside the project the window is on is still not a move; and every
  explicit way of opening a plain folder — ⌘O, `abydos <dir>`, drag and drop,
  Finder, the recents list — still makes a real project of it. The marker test
  answers "where has the shell gone", never "what may be opened".

## Capabilities

### New Capabilities

None. The two rules this changes are both owned by capabilities that already
exist, and neither is a new subject: `terminal` says where a window follows its
terminal, and `sessions` says what a restored session is.

### Modified Capabilities

- `terminal`: the requirement "A window follows its terminal out of the project,
  and nowhere else" changes what it does about a directory in no working copy —
  today it stays where it is, and it will show the folder. The within-a-project
  rule and the driven-run exception are untouched, and both gain a scenario
  rather than losing one.
- `sessions`: gains what a session is for a folder that is not a project — one
  global session, files and not terminals, and nothing written beside the folder.

## Impact

- `Sources/AbydosKit/Project/ProjectRoot.swift` — the markers, the SVN layout
  question, and `projectToFollow` answering with a decision rather than an
  optional URL.
- `Sources/AbydosKit/Run/LaunchStore.swift` — `SessionStore.read`/`write` keyed
  by `URL?`, nil being the one global session.
- `Sources/AbydosKit/Project/Project.swift` — a project knowing whether its root
  is a working copy or a folder it was merely pointed at.
- `Sources/AbydosApp/MainWindowController+Terminal.swift` — three routes through
  `switchProjectBody` where there was one, and `rememberOpenEditors` routing the
  same way.
- `Tests/AbydosKitTests/ProjectRootTests.swift` — two tests invert, and the new
  rules need their own.

Nothing new is depended on. `ProjectRoot.find` keeps its contract, so
`Project.root(containing:)` and the two `AppDelegate` callers improve without
being touched: `abydos notes.txt` inside an SVN checkout will open the checkout
rather than the folder the file sits in.
