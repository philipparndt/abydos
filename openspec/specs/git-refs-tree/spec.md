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

### Requirement: The trailing end of a branch row is one column

The ahead and behind counts, and the symbol that stands in for them, SHALL be
drawn right-aligned on one edge shared by every branch row.

Drawn after the name, a note sits wherever that name happened to end, so reading
a list of them means reading a ragged edge — the same fault the changes tree's
counts had, and fixed the same way.

**A symbol is right-aligned on its own ink, not on the box it is fitted into.**
A tick is taller than it is wide, so a centred fit lands it short of the edge
that the text beside it sits flush on, and the column has a wobble in exactly
the place it exists to remove.

#### Scenario: four rows saying four different things

- **GIVEN** one branch ahead and behind, one never published, one whose upstream
  is gone, and one already merged
- **THEN** all four right-hand marks end on the same x

### Requirement: A branch says whether it has ever been published

A local branch with no upstream SHALL say so on its own row, as a symbol, in the
column the ahead and behind counts are drawn in.

**A symbol rather than the words.** `not published` and `upstream gone` are two
words of English on every row of a list, which is a paragraph nobody reads. They
are `icloud` symbols because both are about the copy on the other machine — one
that was never made, one that has gone — and the words they replace SHALL be in
the row's tooltip, because a symbol is a note somebody has to be able to look
up.

**The counts cannot say it.** Nought ahead and nought behind is what a branch
level with its remote reads, and a branch that has never been near a remote is
the opposite of that — the same confusion `upstream` was given a doc comment
about, drawn rather than typed.

It was readable before only on the repository row and only for the branch the
work tree was on. That row no longer names a branch, and this is the row the
branch is on.

A branch tracking an upstream that has gone SHALL say that instead, for the
reason the repository row gives.

#### Scenario: a branch that has never been pushed

- **GIVEN** a local branch with no upstream, not merged
- **THEN** its row draws a cloud with an upward arrow
- **AND** its tooltip says `never published`

#### Scenario: a branch whose remote branch was deleted

- **GIVEN** a local branch tracking a ref that no longer exists, not merged
- **THEN** its row draws a cloud with a cross

#### Scenario: a branch in step with its upstream

- **GIVEN** a local branch level with the remote
- **THEN** its row says nothing beside its name, as it does today

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

**And the verb SHALL actually be on it.** This specification has said the backup
folder carries deleting the entries older than a given age since it was written,
and `GitBackup.sweep` has done it for as long; the folder's menu offered the
three verbs every folder has and no more. A folder kept for a verb it does not
carry is a row that costs and says nothing.

**The count comes before the choice.** A backup ref is the only copy of what it
holds — that is what it is for — so *delete everything older than a month* is a
sentence nobody can weigh without being told whether it means four refs or forty.

#### Scenario: a single backup ref

- **GIVEN** a repository with exactly one ref under `backup/`
- **THEN** there is a `backup/` folder row with that one ref under it
- **AND** its menu offers deleting the backups older than a chosen age

#### Scenario: choosing an age

- **GIVEN** the backup folder's menu open
- **THEN** each age offered says how many of the backups it would take
- **AND** an age that would take none cannot be chosen

#### Scenario: a prefix that is only a prefix

- **GIVEN** `hotfix/0472` and no other branch beginning `hotfix/`
- **THEN** `hotfix/0472` is one row and there is no `hotfix/` folder

### Requirement: The branch everything merges into is pinned to the top

The refs tree SHALL pin the current branch and then the repository's default
branch above the rest of the local branches.

This is the order `BranchGrouping.arrange` already pins for the branch pill in
the titlebar, and the reason it gives holds here too: they are the two anybody
is most likely to want and the two most annoying to hunt for — the default
especially, since it is almost never the most recently touched and so sinks in
any list ordered by anything else.

**Two lists of the same branches in one window SHALL NOT disagree about their
order.** The pill lists, groups and filters the same branches this pane does;
somebody who has learnt where `main` is in one of them has learnt nothing if the
other puts it elsewhere.

#### Scenario: a branch other than the default checked out

- **GIVEN** a repository on `zeta` whose default branch is `main`
- **THEN** `zeta` is the first local row and `main` is the second
- **AND** the rest follow in the order they had

#### Scenario: the default branch checked out

- **GIVEN** a repository on `main`, which is also its default
- **THEN** `main` appears once, at the top

### Requirement: An unpublished branch counts its own commits

A local branch with no upstream SHALL show how many commits it has that the
default branch has not, in the column its ahead and behind counts would be in.

**Its upstream counts cannot say anything**, there being no upstream: they are
nought and nought, which is what a branch in step with a remote reads. What
somebody wants to know about a branch of their own is how much work is on it
that is not in the branch it will go back into.

The symbol saying it is unpublished stays beside the count. Both are true and
neither implies the other — three commits of your own, and nowhere else holding
a copy of them.

**How far the default branch has moved SHALL NOT be drawn as a down arrow, and
is not drawn at all.** `↑` and `↓` are this pane's remote vocabulary — what is
waiting to go up, what is waiting to come down — and `↓1557` against the default
branch borrows the second to say something else entirely: not *there are commits
to pull* but *main has moved on, and you may want to rebase*. It was read as the
first, which is the only way it can be read on a row where every other arrow
means that.

`↑` survives because it does not change meaning between the two readings:
commits this branch has that the other side has not, which is both the work on
it and exactly what publishing would send.

The figure that cannot be drawn without misleading SHALL be in the row's
tooltip, in words, naming what it is measured against.

It is asked with `%(ahead-behind:)` in the listing already being made, not one
`rev-list` per branch. **That atom arrived in git 2.41 and an older git refuses
the whole command over it** — not the field, the list — so the listing SHALL
fall back to the format without it rather than show no branches at all.

#### Scenario: a branch that has never been pushed

- **GIVEN** a local branch with two commits the default branch has not got
- **THEN** its row reads `↑2` beside the symbol saying it is unpublished

#### Scenario: a branch the default has moved past

- **GIVEN** an unpublished branch the default branch is 1557 commits ahead of
- **THEN** no down arrow is drawn
- **AND** the tooltip says the default branch has moved on by 1557 commits

### Requirement: A branch row offers to open a pull request

A local branch that is not the default branch SHALL offer opening a pull request
from its context menu, wherever the repository has a forge.

**The two halves are one entry each.** Making a pull request from a branch
nobody else can see takes two steps, and having to know that — push first, then
find the compare page — is what makes this the part of the job people leave the
app to do. A branch the forge does not have SHALL offer publishing and opening
in one verb, and one it has SHALL offer opening.

**Whether the forge has it is asked of the listing, not of the upstream.** A
branch is on the forge when a remote-tracking ref of the same name is. That is
the better question in both directions: a branch pushed without `--set-upstream`
is on the host and names no upstream, and a branch whose remote branch was
deleted names one — `[gone]` — and is not there. A compare page for either
absent case is the same 404.

The publish SHALL happen first and the page SHALL NOT be opened if it fails: a
browser tab explaining that a branch does not exist is a worse answer than
saying why it could not be sent.

**The compare page, not an API call.** Which pull request already belongs to a
branch is a question only the host can answer, and answering it needs a token
this app deliberately does not hold.

#### Scenario: a branch that has been published

- **GIVEN** a published local branch and a GitHub remote
- **THEN** its menu offers `Open Pull Request…`

#### Scenario: a branch that has not

- **GIVEN** a local branch with no upstream and a GitHub remote
- **THEN** its menu offers `Publish and Open Pull Request…`

#### Scenario: a branch whose remote branch was deleted

- **GIVEN** a local branch naming an upstream that no longer exists
- **THEN** its menu offers `Publish and Open Pull Request…`, as an unpublished
  branch's does

#### Scenario: the default branch

- **GIVEN** the default branch selected
- **THEN** no pull request is offered, there being nothing to compare it against

### Requirement: A ref is only opened on the forge when the forge has it

Opening a ref's page on the forge SHALL be offered only where a remote-tracking
ref of that name exists.

A page for a branch the host has never heard of is a 404, which is a worse
answer than not offering — and the offer was made on every local branch,
including one that had never been pushed and one whose remote branch had been
deleted.

It is disabled rather than hidden, which is how this menu already says *this
verb, not on this row*. Remote branches and tags are always on the forge, being
what the forge sent.

#### Scenario: a branch that has never been pushed

- **GIVEN** an unpublished local branch and a GitHub remote
- **THEN** `Open on GitHub` is shown and cannot be chosen

#### Scenario: a branch that is there

- **GIVEN** a published local branch, or any remote branch
- **THEN** `Open on GitHub` can be chosen

### Requirement: A branch whose work is already merged is dimmed

A local branch merged into the default branch SHALL be drawn dimmed, and SHALL
carry a tick in the column at the end of the row.

**The tick outranks the other two marks.** A branch whose pull request was
merged and whose remote branch went with it is both merged and upstream-gone,
and of the two only one is what anybody wanted to know: the work is in and this
row can go. `not published` on a branch that is already merged is a note about
how it got there.

**The tick SHALL NOT be dimmed with the rest of the row.** It is the reason the
row is dim, and fading the answer along with the question leaves a grey row with
nothing on it saying why.

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
- **THEN** its row is dimmed and ends in a tick

#### Scenario: a branch that is merged and whose upstream is gone

- **GIVEN** a local branch merged into the default branch, tracking a ref that
  has been deleted
- **THEN** its row ends in a tick rather than a cross

#### Scenario: a branch with work still on it

- **GIVEN** a local branch with a commit the default branch does not have
- **THEN** its row is drawn as it is today

#### Scenario: the branch that is checked out

- **GIVEN** the default branch itself, checked out
- **THEN** it is not dimmed, whatever the reading says

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


### Requirement: Tags are newest first

The TAGS section SHALL order its tags by creation date, newest first, by
default. The date is the tag's own for an annotated tag and the pointed-at
commit's for a lightweight one — `creatordate`, which git is already asked
for.

Alphabetical order made the tag somebody just cut findable only by name, and
lied about versions besides: `v1.10` sorted before `v1.9`. The newest-first
order was already fetched on every refresh and thrown away by the shared
name sort.

#### Scenario: the tag just cut is on top

- **GIVEN** a repository whose newest tag is `v2.0` and whose alphabetically
  first tag is `alpha`
- **WHEN** the TAGS section is read
- **THEN** `v2.0` is the first row

#### Scenario: annotated and lightweight tags share one ordering

- **GIVEN** an annotated tag created after a lightweight one
- **WHEN** the TAGS section is read
- **THEN** the annotated tag is above it

### Requirement: A section header offers its sort orders

The context menu of the TAGS section header SHALL offer the sort orders —
newest first, and by name — with a mark on the one in force, and the LOCAL
and each remote section header SHALL offer the same choice. LOCAL and the
remotes default to by name, which is what they show today.

#### Scenario: switching tags to name order

- **GIVEN** the TAGS section in its default order
- **WHEN** "By Name" is chosen from the header's menu
- **THEN** the tags re-sort alphabetically and the menu marks "By Name"

#### Scenario: local branches by date

- **WHEN** "Newest First" is chosen on the LOCAL header
- **THEN** the local branches order by their tips' dates, newest first

#### Scenario: each section keeps its own choice

- **GIVEN** TAGS set to name order
- **WHEN** the LOCAL section is read
- **THEN** LOCAL's order is unchanged by the choice made on TAGS

### Requirement: The order is remembered

Each section kind's choice — local, remotes, tags — SHALL be kept between
sessions. Choosing again every morning is choosing nothing.

#### Scenario: the choice survives a restart

- **GIVEN** TAGS switched to name order
- **WHEN** the app is quit and reopened on the same project
- **THEN** TAGS is in name order and its menu marks "By Name"

### Requirement: The order reaches everything the section shows

The chosen order SHALL apply within each folded prefix level (folders keep
their place before leaves and their own name order — a folder has no date),
SHALL apply to the filtered, flattened list, and the LOCAL section's order
SHALL be the order the titlebar branch pill uses, keeping the rule that two
lists of the same branches in one window do not disagree.

#### Scenario: date order inside a folder

- **GIVEN** local branches `feature/old` and `feature/new`, in date order
- **WHEN** the `feature` folder is opened
- **THEN** `new` is above `old`

#### Scenario: the filtered list obeys the choice

- **GIVEN** TAGS in newest-first order and a filter that matches three tags
- **WHEN** the flattened matches are shown
- **THEN** they are newest first

#### Scenario: the pill agrees with the tree

- **GIVEN** LOCAL switched to newest first
- **WHEN** the titlebar branch pill's list is opened
- **THEN** the branches are in the same order the LOCAL section shows
