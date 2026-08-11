<!-- What this item changes about `version-control`. Folded into
     .abydos/backlog/spec/version-control.md by `abydos-backlog done`.

     Nothing had been said about version-control before this, so this is
     all ADDED — and only the part of it this item establishes. What the
     rest of the git support does is still only written in the code.
-->

## ADDED Requirement: The working copy is shown as the folders it changed

The commit view is two trees — unstaged above, staged below — of the folders
the changes are in, relative to the work tree root. Only folders with a change
under them are rows: the whole project would put a commit of three files at the
bottom of the tree the navigator already shows.

Folders come before files and then in name order, the arrangement the project
tree uses. A chain of folders with one child each stays a chain rather than
folding into one row: a folded row would not be a folder, and it would take away
the row that stages the outer folder on its own.

The trees arrive unfolded. A pane that shows five folder names where the flat
list showed twenty files has said less than it did before.

### Scenario: one file changed, several folders deep

- **Given** only `Sources/AbydosKit/Git/GitBlame.swift` has changed
- **When** the commit view is opened
- **Then** the unstaged tree is `Sources`, `AbydosKit`, `Git`, `GitBlame.swift`
- **And** no folder without a change under it appears

## ADDED Requirement: Staging a folder stages everything under it

Staging or unstaging a folder acts on every change beneath it, including a
deletion, because the folder is handed to git as one path. A selection holding
both a folder and files under it hands over the folder alone.

### Scenario: a folder with two changed files under it

- **Given** `Sources/Git` has two changed files under it, one of them deleted
- **When** the folder is selected and staged
- **Then** both are in the index, the deletion as a deletion
- **And** the folder is no longer a row in the unstaged tree

## ADDED Requirement: A folder says how much of it is on this side of the index

Git has no half-staged directory — it does not track directories at all — so a
folder row says so itself. It carries the number of changes under it on its own
side of the index, and when some of what changed under it is on the other side
it reads `4 of 6` instead of `6`, in the colour a modified file is written in,
with the whole of it in words on the tooltip.

Changes are counted rather than paths. A file staged and then edited again is
one path in both lists, and counting paths would call its folder whole while a
commit would leave the second edit behind.

### Scenario: four of six staged

- **Given** six files have changed under `Sources`, four of them staged
- **When** the commit view is opened
- **Then** `Sources` reads `4 of 6` under Staged and `2 of 6` under Unstaged

### Scenario: a file staged and then edited again

- **Given** the only change under `Sources` is a file staged and then edited
- **Then** `Sources` reads `1 of 2` in both lists

## ADDED Requirement: The commit view keeps its place while files are written

The trees are rebuilt whenever the working copy changes, which is on every
filesystem event. A folder folded shut by hand stays shut across a rebuild, one
folded open stays open, and what is inside a folder opened again by hand comes
back as it was. The selection is carried across by path.

Staging takes rows away — a folder with nothing left under it stops being a row
— so when everything that was selected has gone the selection lands on the
nearest row above where it was, rather than nowhere.

### Scenario: a file is saved while a folder is folded shut

- **Given** `Sources/AbydosKit` has been folded shut in the unstaged tree
- **When** something else is staged and the tree is built again
- **Then** `Sources/AbydosKit` is still shut and everything else is still open

### Scenario: the selected folder is staged away

- **Given** a folder is selected in the unstaged tree
- **When** it is staged, and nothing under it is left unstaged
- **Then** the selection is on the row that was above it
