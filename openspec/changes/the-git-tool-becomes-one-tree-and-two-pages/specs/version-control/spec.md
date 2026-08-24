## MODIFIED Requirements

### Requirement: The working copy is shown as the folders it changed

The working copy SHALL be shown as the folders it changed.

The commit page is two trees — unstaged above or beside staged — of the folders
the changes are in, relative to the work tree root. Only folders with a change
under them are rows: the whole project would put a commit of three files at the
bottom of the tree the navigator already shows.

**Where this is shown has moved.** It was the sidebar's commit view; it is now
the commit tense of the git page in the editor area, so the list of changes sits
beside the diff of the selected one rather than above a diff opened elsewhere.
The refs tree in the sidebar shows the same folders under its working-copy row,
built from the same tree, so what is said here holds in both.

Folders come before files and then in name order, the arrangement the project
tree uses. A chain of folders with one child each stays a chain rather than
folding into one row: a folded row would not be a folder, and it would take away
the row that stages the outer folder on its own.

The trees arrive unfolded. A pane that shows five folder names where the flat
list showed twenty files has said less than it did before.

#### Scenario: one file changed, several folders deep

- **Given** only `Sources/AbydosKit/Git/GitBlame.swift` has changed
- **When** the commit page is opened
- **Then** the unstaged tree is `Sources`, `AbydosKit`, `Git`, `GitBlame.swift`
- **And** no folder without a change under it appears

#### Scenario: the same change in the sidebar

- **Given** the same one changed file
- **When** the working-copy row in the refs tree is expanded
- **Then** the same folders are its children

### Requirement: Changes can be thrown away, from the unstaged list only

Changes SHALL be able to be thrown away, from the unstaged list only, and a
discard SHALL leave a backup ref behind.

The menu discards what a row covers: a file, or a folder and everything under it.
It is offered in the unstaged list and nowhere else.

**A discard is destructive**, so it goes through the safety net: what it takes is
counted in the dialog, and the working copy is captured with `git stash create`
into a ref under `backup/` before anything is restored. `stash create` writes a
commit without touching the working copy or the stash list, so nothing moves
before the ref exists.

Discard restores the work tree *from the index*, so over a staged row it would
throw away nothing that is staged — the change would survive, staged, and the
row would not go away. Meaning `restore --staged --worktree` there instead was
the other way to make it honest, and it is not what happens: a file staged and
then edited again is a row in each list, and discarding it from the staged row
would also take the later edit, which is only shown in the other one. Unstaging
first is recoverable and is the top item of the same menu. The diff view hides
*Discard Selected Lines* over a staged hunk for the same reason, so the word
means one thing in this window.

It is not offered over a conflict either. `git checkout` refuses an unmerged
path, so the entry would be one that always fails, and throwing away a
half-resolved merge is a question with more than one answer.

#### Scenario: a modified file

- **Given** a tracked file with unstaged changes
- **When** it is discarded from the context menu and the confirmation is agreed
- **Then** the file holds what the index holds for it
- **And** it is no longer a row in the unstaged tree
- **And** a ref under `backup/` holds what it held before

#### Scenario: the same file's staged row

- **Given** a file that is staged and then edited again, so it is a row in both
  trees
- **When** the menu is opened on its row under Staged
- **Then** there is no discard entry

#### Scenario: an unresolved merge

- **Given** a file git reports as unmerged
- **When** the menu is opened on it
- **Then** there is no discard entry

## ADDED Requirements

### Requirement: A stash says what is in it and whether it will still apply

A stash SHALL be able to be looked into before it is taken back, and SHALL say
whether it would apply cleanly over the working copy as it stands.

`applyStash` restores blind today: three entries called "wip" are a guessing
game, and applying one into a mess that then has to be untangled is the failure
worth engineering away. The files a stash holds are rows under it, each opening
that stash's diff for it.

**Where the check says it would conflict, branching from the stash SHALL be
offered instead.** `git stash branch` makes a branch at the commit the stash was
taken from and applies it there, so it cannot conflict — which is the right
answer for an old stash and exactly the case the check has just found.

#### Scenario: a stash that still applies

- **GIVEN** a stash whose files do not overlap the working copy
- **WHEN** its row is selected
- **THEN** it says it applies cleanly and offers apply and pop

#### Scenario: a stash that would conflict

- **GIVEN** a stash overlapping two changed files
- **WHEN** its row is selected
- **THEN** it names the two files it would conflict in
- **AND** branching from the stash is offered

### Requirement: A branch that cannot be switched to over a dirty tree offers the stash

A checkout git refuses over a dirty working copy SHALL offer to stash the
changes, switch, and put them back on return.

`BranchInUse` already set this principle for the one refusal the app could act
on: where a refusal is one the app can do something about, offer the action
rather than report the refusal. A dirty tree is the second such refusal, and it
is where most stashes come from.

#### Scenario: switching with changes in the way

- **GIVEN** three changed files that the target branch would overwrite
- **WHEN** that branch is checked out
- **THEN** stashing them and switching is offered, with putting them back on
  return
- **AND** switching and leaving them behind is offered with a backup ref

### Requirement: A tag can be made, moved onto a ref, and deleted

Tags SHALL be able to be created at a commit or a ref, moved to another, and
deleted, and the sheet that moves one SHALL resolve the target before it is
agreed to.

`GitTags.recreate` already takes anything git can resolve — a commit, a branch, a
tag — so pointing `v1` at `main` has always worked. What stopped anybody doing it
was a bare text field pre-filled with a guess and no way to see where the tag was
about to land. The field is a picker over the refs already loaded, and what the
chosen source resolves to is shown beneath it through `GitTags.describe`.

Moving a tag SHALL say what it is leaving and where that has been kept.

#### Scenario: pointing a moving tag at a branch

- **GIVEN** a tag `v1` and a branch `main`
- **WHEN** the tag's move sheet is opened and `main` chosen
- **THEN** the commit and subject `main` resolves to are shown before agreeing
- **AND** agreeing points `v1` there and says what it left, and where
