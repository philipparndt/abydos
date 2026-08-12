# Version control

Git, driven from the sidebar: the commit view stages and commits, with the
branches and the history beside it. Only the commit view is written down here
so far. The rest of the git support exists and is not described yet; it belongs
in this file as it is next worked on.

## Requirement: The working copy is shown as the folders it changed

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

## Requirement: Staging a folder stages everything under it

Staging or unstaging a folder acts on every change beneath it, including a
deletion, because the folder is handed to git as one path. A selection holding
both a folder and files under it hands over the folder alone.

### Scenario: a folder with two changed files under it

- **Given** `Sources/Git` has two changed files under it, one of them deleted
- **When** the folder is selected and staged
- **Then** both are in the index, the deletion as a deletion
- **And** the folder is no longer a row in the unstaged tree

## Requirement: A folder says how much of it is on this side of the index

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

## Requirement: The commit view keeps its place while files are written

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

## Requirement: One question answers which branch the work tree is on

Everything that needs the branch — the titlebar, the branch menu, the project
switcher, the push button — asks `GitRepository.head(in:)`, and it answers in
three states rather than two: a branch, a branch with nothing committed on it,
and no branch at all.

It asks git `symbolic-ref --short HEAD`, which reads the reference HEAD points
at. `rev-parse --abbrev-ref HEAD` is the obvious question and the wrong one: it
resolves the commit and only then names it, so in a repository that has been
created and not yet committed to it fails outright, while the branch name is
sitting in `.git/HEAD`. `branch --show-current` would answer the same thing, but
it is porcelain, it needs git 2.22, and it prints an empty line where
`symbolic-ref` exits non-zero.

A detached HEAD is not a branch and has no name. `symbolic-ref` fails there,
which is how it is told apart — the old question answered the literal string
`HEAD`, and each caller separately had to know to discard it.

### Scenario: a repository with nothing committed yet

- **Given** a repository created with `git init -b main` and no commit made
- **When** the branch is asked for
- **Then** it is `main`, and it is known to have nothing on it

### Scenario: a commit checked out directly

- **Given** the work tree is on a detached HEAD
- **When** the branch is asked for
- **Then** there is no branch name

## Requirement: A branch with no commits on it shows, quietly

The titlebar names the branch of a repository that has nothing committed to it,
because the name is a fact from the moment `git init` runs, and showing nothing
made a real repository look like a folder that was not one.

It shows dimmed, in the weight the keyboard hint beside it is drawn in, and the
tooltip says why. The name at full weight would read as an ordinary branch, and
on this one the commit page, the push button and the branch menu each behave
differently.

The branch menu opens on such a repository and names the branch, ticked and not
selectable. `git branch` lists refs and an unborn branch has none, so it appears
in no list git can produce — and a menu that refused to open would leave the
places this repository can be opened, on the host and in Fork, unreachable.

### Scenario: the titlebar of a freshly created repository

- **Given** a project whose repository has no commits
- **When** the window opens
- **Then** the titlebar reads the branch's name, dimmed
- **And** its tooltip says there are no commits yet

## Requirement: Push says which branch it cannot send

A branch with nothing committed on it cannot be pushed — there is no ref to
send, and `git push -u origin main` fails. The button is disabled, and it says
which branch is empty rather than offering the generic "Push this branch" that
a repository with no branch at all gets.

Amending is off for the same reason and is spelt out the same way: there has to
be a commit to amend, and the checkbox is disabled with a tooltip saying so
rather than letting git's `fatal: You have nothing to amend` reach the screen.

### Scenario: a repository with a remote and no commits

- **Given** a repository with an `origin` and nothing committed
- **When** the commit page is opened
- **Then** the push button is disabled and reads `Push`
- **And** its tooltip names the branch and says it has no commits yet
- **And** the Amend checkbox is disabled
