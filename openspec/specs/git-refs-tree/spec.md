# Git refs tree

## Purpose

The one sidebar outline behind the git tool: its sections, its branch-name folders, and what each row says about itself without being opened.

## Requirements

### Requirement: One tree holds everything the repository has

The git tool SHALL be one outline holding the working copy, the stashes, local
branches, each remote's branches, tags, worktrees and the backup folder, and
SHALL NOT be split across more than one tool item.

Three tool windows for one repository made the first question "which pane answers
this" rather than the question somebody had. The tree answers it by being the
only place to look.

Every row SHALL say enough to be understood without being opened: a branch its
ahead and behind counts and the subject of the commit it points at, a stash the
branch it came off and how long ago, a tag what it points at.

#### Scenario: opening the git tool

- **GIVEN** a repository with branches, a tag, a stash and a worktree
- **WHEN** the git tool is opened
- **THEN** all of them are sections of one outline

### Requirement: What holds files expands to them; what is a ref opens a page

A row holding files SHALL expand to those files, and a row that is a ref SHALL
open a page rather than expanding.

The working copy expands to staged and unstaged and then to the folders it
changed. A stash expands to what it would restore. A file opens its diff where
diffs already open. A branch or a tag opens the log.

#### Scenario: looking inside a stash

- **GIVEN** a stash of four files
- **WHEN** its row is expanded
- **THEN** the four files are rows under it
- **AND** selecting one opens that stash's diff for it

#### Scenario: pressing return on a branch

- **GIVEN** a branch row
- **WHEN** return is pressed on it
- **THEN** the log page opens scoped to that branch

### Requirement: Branch names fold on their slashes

Branch names SHALL be shown as a tree folded on `/`, in the arrangement the
project tree and the changes tree already use.

`feature/tags` and `feature/stash-preview` sit under a `feature/` row.
`GitChangeNode` already builds this tree from `/`-separated paths and keeps
collapse state by path across a rebuild; a branch name is a path, and a third
builder that sorted differently would be a difference nobody could explain.

**A folder holding exactly one branch SHALL stay flat.** `hotfix/0472` is one
row. A folder that exists to hold a single row has turned one row into two and
said nothing.

Tags and the backup folder fold the same way.

#### Scenario: two branches under one prefix

- **GIVEN** `feature/tags` and `feature/stash-preview`
- **THEN** there is a `feature/` row with the two of them under it

#### Scenario: one branch under a prefix

- **GIVEN** `hotfix/0472` and no other branch beginning `hotfix/`
- **THEN** `hotfix/0472` is one row and there is no `hotfix/` folder

### Requirement: Filtering flattens the tree

Typing in the filter SHALL show matching refs as full names with no folders.

A tree you have to expand to reach a name you have just typed is worse than no
tree.

#### Scenario: filtering to a nested branch

- **GIVEN** the filter text `tags`
- **THEN** `feature/tags` is a row showing its whole name
- **AND** there is no `feature/` folder row

### Requirement: A folder of branches is an object with verbs of its own

A folder row SHALL carry the verbs that make sense for a set of branches.

Expand and collapse all, push all, delete those already merged, copy the prefix.
The backup folder carries deleting those older than a given age.

#### Scenario: the backup folder

- **GIVEN** a `backup/` folder holding refs from several weeks
- **WHEN** its menu is opened
- **THEN** it offers to delete those older than a chosen age

### Requirement: A conflicted working copy says so, and offers the three ways out

A working copy holding a conflict SHALL say so in the git tool's header, name
how many files are conflicted, and offer to open them, to open the repository in
Fork, and to copy a prompt describing the conflict.

Nothing on screen says a merge is half-done today. The three offers are the
three things somebody actually does next, and they are deliberately not four:
**opening the files** is the work; **Fork** is where this change has already
said a three-way merge editor belongs, so the handoff has a home rather than
being a dead end; and **copying a prompt** — the conflicted hunks with both
sides and enough context to be answerable — hands the conflict to an agent in
this app's own terminal, which is the thing this app is for.

Aborting is not offered here. The banner is about resolving; abandoning belongs
on the operation that started the merge, where the count of what would be lost
is known and can be said.

#### Scenario: a merge stops in two files

- **GIVEN** a working copy git reports as having two unmerged paths
- **THEN** the git tool's header says two files are conflicted
- **AND** it offers to open them, to open in Fork, and to copy a prompt

#### Scenario: Fork is not installed

- **GIVEN** a machine with no Fork
- **THEN** the Fork offer is absent rather than present and failing

#### Scenario: nothing is conflicted

- **GIVEN** a working copy with no unmerged paths
- **THEN** there is no banner
