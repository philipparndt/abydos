## Why

`BacklogPane` is built for one project and never told about another:

    init(projectRoot: URL) {
        self.backlog = Backlog(projectRoot: projectRoot)
        self.openSpec = OpenSpec(projectRoot: projectRoot)

Both are `let`. `showBacklog()` finds the session it made the first time and
calls `pane.reload()`, which re-reads **the folders it was born with** — so a
reload after a project switch is a reload of the project you left. The pane has
to be closed and reopened, which is the report exactly.

Nothing in `switchProject(to:followingTerminal:)` says otherwise. That function
does a great deal — captures the editor session, the terminals, the tmux window,
the subproject path, the selected configuration, the Xcode destinations, the
breakpoints; restores the arriving project's — and mentions the backlog nowhere.
Panel sessions survive: `sessions.removeAll()` happens in `shutdown()`, which is
called when the *window* closes, so the pane is still there, still showing the
other project's board.

**And the same fault is in the search pane, where it is worse.** `SearchPane` has
`private let projectRoot: URL` and its own `ProjectSearch(root:)`, and the panel
caches it:

    private(set) var existingSearchPane: SearchPane?
    func makeSearchPaneIfNeeded() -> SearchPane? {
        if let existingSearchPane { return existingSearchPane }

A stale board shows work that is not yours. A stale search **opens files in a
tree you are not in** — which is the thing this project already has a house rule
about, written after an agent renamed a file in a real `~/.config/zshutil`.

`load(project:)` already tells the panes that expect to be told —
`scratchesPane?.setProject(project.root)` is on the line above
`bottomPanel.setWorkingDirectory(project.root)`. There is a pattern here; the
backlog and the search pane are simply not in it.

Reported as: navigate to another repository with terminal-follows-project on,
and the backlog stays behind.

## What Changes

- **The backlog pane is told when the project changes**, and re-reads that
  project's `.abydos/backlog` and `openspec/changes` instead of the old one's.
  Everything the pane worked out at birth is worked out again: whether the
  project has a backlog at all, whether it has an OpenSpec directory, and
  therefore which of the two the switch is even offered for.
- **Its watchers move with it.** `watch()` only starts a watcher where there is
  none, so a pane that kept its old ones would go on being woken by the project
  it left and would never notice the one it is in. This is the part that fails
  quietly if it is forgotten.
- **The search pane goes too, and this is the one to argue about.** It is the
  same fault with the same one-line fix, and it is included because "search this
  project" answering with another project's files is worse than a stale board,
  not because it was asked for. Say so and I will split it out.
- **Nothing is thrown away that a person put there.** A pane is re-pointed, not
  rebuilt: no flicker, no tab reopening, and the search pane's query and results
  belong to the tree they came from, so they are cleared rather than left
  looking like answers about the new one.
- **Not proposed: rebuilding the panes on switch.** Making a new one would work
  and would lose the tab's place in the strip, which is a person's arrangement.
- **Not proposed: a general "every pane is project-bound" mechanism.** Two panes
  and one existing pattern (`setProject`) is not enough to justify inventing a
  protocol; a third is the moment to.

## Capabilities

### New Capabilities
<!-- None. -->

### Modified Capabilities

- `backlog`: which project's records the pane is showing, which the spec has so
  far only said in terms of "the project" without saying what happens when that
  changes.
- `search`: the same, for the pane that opens files.

## Impact

- `Sources/AbydosApp/Panel/BacklogPane.swift` — `backlog` and `openSpec` stop
  being `let`; `init` splits so its tail can be run again; `watcher` and
  `openSpecWatcher` are stopped and dropped, not kept.
- `Sources/AbydosApp/Panel/SearchPane.swift` — `projectRoot` and `search` the
  same, and whatever holds the current results.
- `Sources/AbydosApp/Panel/BottomPanel.swift` — `setWorkingDirectory` is already
  the place the panel is told; the panes it holds are told from there.
- `Sources/AbydosApp/MainWindowController.swift` — `load(project:)`, which
  already calls `scratchesPane?.setProject`.
- Nothing new on a drawing path, and no new dependency. One extra directory
  listing per switch, which is what opening the pane costs today.
