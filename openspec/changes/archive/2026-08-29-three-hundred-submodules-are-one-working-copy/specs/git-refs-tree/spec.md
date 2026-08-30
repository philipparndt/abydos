# git-refs-tree

## MODIFIED Requirements

### Requirement: The repository is the first row, and it does not scroll away

The tree SHALL begin with a row for the repository, and that row SHALL stay at
the top of the pane while the rest of the tree scrolls.

It says how far the branch the work tree is on is from its upstream, in words —
`3 behind · 1 ahead`, `level`, `upstream gone`, or that there is no remote — and
it is the control that follows from that: fetch when level, pull when behind,
push when ahead.

**It SHALL NOT name the project or the branch.** Both are written in the
titlebar a few points above it, so a repository with nothing to report drew a
glyph and two words already on screen. What is left is the one thing nothing
else in the window says and the thing this row is pinned for.

**An upstream that is gone SHALL NOT read as level.** `%(upstream:track)` says
`[gone]` in place of the counts, so the naive reading is nought behind and
nought ahead — a sentence about a ref that is not there. It is also the control: fetch when level, pull when behind, push when
ahead, which is what the button above the tree used to be.

**Drawn as a row because a verb hangs off the row that draws its object**, which
is what this specification already says about folders of branches and what the
traffic button's own comment gave as the reason it exists — the repository had
no row, so its verb needed a button. Given a row, it does not.

**Pinned because how far you are from the remote is state.** Everything else in
this tree is a thing you go and look at; this is a thing you need to have
noticed. A repository row that scrolls out of sight behind forty branches is the
fault the header was avoiding, reintroduced.

**Where the repository holds submodules the row SHALL say so and how many.** The
count is the one thing about a superproject that changes what everything below it
means: `level` on a superproject is a true sentence about the superproject and
says nothing about the forty services under it, and a reader who does not know
this is a superproject has no reason to look further.

**The row SHALL NOT gain a second verb for it.** This row's action is the remote
traffic — fetch when level, pull when behind, push when ahead — and that is the
whole reason this specification draws the repository as a row rather than a
header: a verb hangs off the row that draws its object. A second verb here would
dilute the one thing the row is pinned for. The way to the overview hangs off the
row that draws *that* object, which is the Submodules section's own header.

**The superproject's own distance is still what the row states.** It is not
summed with its submodules': `3 behind` about a superproject and `3 behind`
averaged over two hundred repositories are different facts, and only the first
is one this row can state honestly. What the submodules are doing is the
overview's sentence to say, and the row carries the way to it.

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

#### Scenario: an upstream that has been deleted

- **GIVEN** a branch tracking a remote branch that no longer exists
- **THEN** the row says the upstream is gone rather than that it is level
- **AND** pressing it fetches

#### Scenario: nothing to report

- **GIVEN** a branch level with its upstream
- **THEN** the row says `level` and offers `Fetch`
- **AND** it does not repeat the project or the branch the titlebar names

#### Scenario: a superproject of two hundred submodules

- **GIVEN** a superproject holding 200 submodules, its own branch level
- **WHEN** the git tool is opened
- **THEN** the row says it holds 200 submodules
- **AND** the distance it states is the superproject's own, not a sum

#### Scenario: the row keeps the verb it had

- **GIVEN** the same superproject, its branch level with its upstream
- **THEN** the row's verb is still `Fetch`
- **AND** the way to the overview is the Submodules section's header, not this row

## ADDED Requirements

### Requirement: The submodules are a section of the tree, and they are not two hundred branches

The tree SHALL hold the submodules as a section of its own, and that section
SHALL NOT expand into every submodule's refs.

`One tree holds everything the repository has` is why they belong here: a
submodule is something the repository has, and a second tool for them would
reintroduce the "which pane answers this" question that requirement exists to
kill.

But two hundred submodules each holding branches, stashes, tags and worktrees is
not a tree anybody scrolls. So the section SHALL show only those submodules that
have something to report — changed, conflicted, ahead of their upstream, or with
a gitlink the superproject has not recorded — and SHALL say how many are clean
rather than list them.

The section header SHALL carry the verb that opens the overview, which is where
all two hundred are readable.

A submodule row SHALL expand to its own changed files, and SHALL NOT expand to
its branches. Opening the submodule's own refs is opening that repository, which
is a different thing from reading this one.

#### Scenario: an estate mid-refactoring

- **GIVEN** a superproject of 200 submodules, six changed and one conflicted
- **WHEN** the tree is opened
- **THEN** the submodules section lists those seven
- **AND** says that 193 are clean, without listing them

#### Scenario: expanding a changed submodule

- **GIVEN** the `svc-47` row in that section
- **WHEN** it is expanded
- **THEN** its changed files are its children
- **AND** its branches are not

#### Scenario: a repository with no submodules

- **GIVEN** a repository whose index holds no gitlink
- **THEN** the tree has no submodules section
