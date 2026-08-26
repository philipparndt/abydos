# git-refs-tree

## ADDED Requirements

### Requirement: The repository is the first row, and it does not scroll away

The tree SHALL begin with a row for the repository, and that row SHALL stay at
the top of the pane while the rest of the tree scrolls.

It says which project, which branch the work tree is on, and how far that branch
is from its upstream in words — `3 behind · 1 ahead`, `level`, or that there is
no remote. It is also the control: fetch when level, pull when behind, push when
ahead, which is what the button above the tree used to be.

**Drawn as a row because a verb hangs off the row that draws its object**, which
is what this specification already says about folders of branches and what the
traffic button's own comment gave as the reason it exists — the repository had
no row, so its verb needed a button. Given a row, it does not.

**Pinned because how far you are from the remote is state.** Everything else in
this tree is a thing you go and look at; this is a thing you need to have
noticed. A repository row that scrolls out of sight behind forty branches is the
fault the header was avoiding, reintroduced.

#### Scenario: a branch behind and ahead of its upstream

- **GIVEN** a work tree on `main`, three commits behind and one ahead
- **WHEN** the git tool is opened
- **THEN** the first row names the project and `main`, and says three behind and
  one ahead
- **AND** pressing it pulls, because behind comes first

#### Scenario: scrolling the tree

- **GIVEN** a repository with more branches than the pane can show
- **WHEN** the tree is scrolled to the bottom
- **THEN** the repository row is still at the top of the pane

#### Scenario: a repository with no remote

- **GIVEN** a repository with no remote configured
- **THEN** the row says so, and offers nothing to press

### Requirement: The working copy row carries the verb that acts on it

The working copy row SHALL offer opening the commit view whenever it has
anything to commit, and SHALL name that action after what is done there rather
than after committing.

Committing is the most frequent act in this pane and it had no visible
affordance at all: it was reachable from the row's context menu, which has to be
guessed at, and from `⇧⌘K`, which has to be known.

**And the words matter.** `Commit…` reads as *commit now, after a
confirmation*. Nothing is committed by pressing it — it opens the view where
hunks are chosen and a message is written, and committing happens there, later,
by a different press. The row already says how many changes there are, so the
action reads as a sentence beside it: `Review 1 change…`.

The context menu and the keyboard SHALL use the same words, so that the three
ways to the same place do not disagree about what it is.

#### Scenario: a working copy with changes

- **GIVEN** a working copy with one changed file
- **THEN** its row offers `Review 1 change…`
- **AND** pressing it opens the commit view without committing anything

#### Scenario: a clean working copy

- **GIVEN** a working copy with nothing changed
- **THEN** the row offers nothing to press

#### Scenario: the other two ways in

- **GIVEN** the same working copy
- **WHEN** its context menu is opened, and when `⇧⌘K` is pressed
- **THEN** both say and do what the row's action says and does

### Requirement: A section row carries the verb that makes a new one

The `LOCAL` section row SHALL offer making a branch.

This specification already says a folder of branches is an object with verbs of
its own. A section is a folder that git made rather than a name that folded, and
the verb that belongs to the set of local branches is the one that adds to it —
which is what the `New Branch…` button above the tree was.

#### Scenario: making a branch from the section

- **GIVEN** the git tool open
- **WHEN** the `LOCAL` row's action is used
- **THEN** the same dialog opens as the button above the tree opened

### Requirement: A row's action can be reached from the keyboard

Every action a row offers SHALL be reachable without a mouse.

An action drawn on a row when the pointer is over it is a mouse-only feature,
and these panes have just been fixed not to be: the arrows walk them, `←` and
`→` open and shut them, and a verb that only a pointer can reach undoes that.

`⏎` is taken — on a branch it checks it out — so a row that has both a default
gesture and an action needs the two told apart rather than overloaded. What the
keyboard offers SHALL be the same set the pointer offers, and the context menu
remains the place where everything is named.

#### Scenario: the repository row from the keyboard

- **GIVEN** the repository row selected and a branch behind its upstream
- **WHEN** the key that fires a row's action is pressed
- **THEN** it pulls, as pressing the row does

#### Scenario: a branch row, which has both

- **GIVEN** a branch row selected
- **THEN** `⏎` checks it out, and the row's other verbs are reachable by their
  own gesture and from the context menu

### Requirement: A folder the tree names in its own right is never folded away

A folder that carries verbs of its own SHALL keep its row however few branches
are under it.

The rule that a folder holding exactly one branch stays flat is right for a
prefix that happened to be shared: `hotfix/0472` is one row, and a folder made
to hold it would have turned one row into two and said nothing.

**It is wrong for a folder that is an object.** `backup/` is made by this
program, and this specification already gives it a verb — deleting the entries
older than a given age. Fold it away and the verb goes with it: one backup ref
means no backup folder, and no way to sweep the backups. The question is not how
many children a folder has but whether the tree names it in its own right.

#### Scenario: a single backup ref

- **GIVEN** a repository with exactly one ref under `backup/`
- **THEN** there is a `backup/` folder row with that one ref under it
- **AND** the folder's own verbs are on it

#### Scenario: a prefix that is only a prefix

- **GIVEN** `hotfix/0472` and no other branch beginning `hotfix/`
- **THEN** `hotfix/0472` is one row and there is no `hotfix/` folder

### Requirement: A branch whose work is already merged is dimmed

A local branch merged into the default branch SHALL be drawn dimmed.

A merged branch is finished: there is nothing on it that is not somewhere else.
Saying so where the branch already is beats the two alternatives — moving it,
which means somebody hunts for a branch that was where they left it until it
merged, and hiding it, which means a branch disappears at the moment it becomes
safe to delete.

It is drawn from one reading of what is merged, taken with the reads the pane
already does. A branch the reading has not covered SHALL draw as it does now,
so a slow or failed answer costs appearance rather than correctness.

#### Scenario: a branch that has been merged

- **GIVEN** a local branch whose commits are all in the default branch
- **THEN** its row is dimmed

#### Scenario: a branch with work still on it

- **GIVEN** a local branch with a commit the default branch does not have
- **THEN** its row is drawn as it is today

#### Scenario: the branch that is checked out

- **GIVEN** the default branch itself, checked out
- **THEN** it is not dimmed, whatever the reading says

## MODIFIED Requirements

### Requirement: Filtering flattens the tree

Typing in the filter SHALL show matching refs as full names with no folders.

A tree you have to expand to reach a name you have just typed is worse than no
tree.

**The filter SHALL be opened with `⌘F` rather than held in a field above the
tree.** It was a permanent row — 22 points plus its inset, in a pane whose whole
job is a list — for something reached occasionally, and it was the second branch
filter in the window: the branch pill opens a popover that lists, groups and
filters branches already, from the titlebar, without this pane being open.

Opened, it sits over the list, closes on `esc` and closes when it is emptied, as
the editor's find bar does. What it does once open is unchanged.

#### Scenario: filtering to a nested branch

- **GIVEN** the filter open and the text `tags`
- **THEN** `feature/tags` is a row showing its whole name
- **AND** there is no `feature/` folder row

#### Scenario: opening and closing it

- **GIVEN** the git tool with no filter showing
- **WHEN** `⌘F` is pressed
- **THEN** a filter opens over the list with the keyboard in it
- **AND** `esc` closes it and the tree is unfiltered again

#### Scenario: the tree's own height

- **GIVEN** the git tool with no filter showing
- **THEN** the tree begins at the top of the pane, under the repository row, and
  nothing else takes height above it
