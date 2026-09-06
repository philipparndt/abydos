# Version control

## Purpose

The working copy and history of a git repository. The commit view has moved
into the git page's commit tense — see `git-pages` — and this file now covers
what stayed behind: the shape of the two file trees, discarding, stashing, and
tags. The refs tree itself, the safety net around destructive operations, and
remote traffic are their own capabilities — `git-refs-tree`, `git-safety`,
`git-remote-traffic` — because each is a fact about the whole repository rather
than about the working copy alone.
## Requirements
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

**A change carries the repository it is in.** In an estate the paths in these
trees come from several repositories, and the same folder name occurs in two
hundred of them: `src/main/java` under `svc-3` and under `svc-47` are different
folders and must not become one row. So a submodule with changes under it is a
row above its folders, named by its path, and the folders beneath it are relative
to that repository's own work tree.

**The repository row exists only where there is a repository to name.** A project
with no submodules has the trees it has always had, with no row added above them:
the estate is one repository, and a level of tree with one child that is always
the same child says nothing.

The trees arrive with the repository rows unfolded, for the reason the folders do
— though an estate large enough that two hundred repositories have changes is one
where the overview, not this tree, is the place to look.

#### Scenario: one file changed, several folders deep

- **Given** only `Sources/AbydosKit/Git/GitBlame.swift` has changed
- **When** the commit page is opened
- **Then** the unstaged tree is `Sources`, `AbydosKit`, `Git`, `GitBlame.swift`
- **And** no folder without a change under it appears

#### Scenario: the same change in the sidebar

- **Given** the same one changed file
- **When** the working-copy row in the refs tree is expanded
- **Then** the same folders are its children

#### Scenario: the same path changed in two submodules

- **Given** `src/main/java/Log.java` changed under both `svc-3` and `svc-47`
- **When** the commit page is opened
- **Then** `svc-3` and `svc-47` are separate rows, each with its own folders
- **And** neither file appears under the other's row

#### Scenario: a project with no submodules

- **Given** a project whose index holds no gitlink
- **When** the commit page is opened
- **Then** the trees begin at the folders, with no repository row above them

### Requirement: Staging a folder stages everything under it

Staging a folder SHALL stage everything under it, in the repository that owns it.

Staging or unstaging a folder acts on every change beneath it, including a
deletion, because the folder is handed to git as one path. A selection holding
both a folder and files under it hands over the folder alone.

**A folder is handed to the repository that owns it, with a path relative to
that repository.** `git add` resolves a pathspec against the repository it runs
in, so a folder inside a submodule staged in the superproject is the `warning:
could not open directory 'sub/sub/'` failure `Project.gitRoot` records. A
selection spanning several repositories is grouped by owner and staged with one
command per repository — six processes for a hundred paths across six
repositories, not a hundred.

**A submodule's own row stages that submodule's changes, not its gitlink.**
Selecting the `svc-47` row stages what changed inside `svc-47`. Moving the
superproject's gitlink is a consequence of committing there, not of staging here,
and the two are not the same act.

#### Scenario: a folder with two changed files under it

- **Given** `Sources/Git` has two changed files under it, one of them deleted
- **When** the folder is selected and staged
- **Then** both are in the index, the deletion as a deletion
- **And** the folder is no longer a row in the unstaged tree

#### Scenario: a folder inside a submodule

- **Given** `svc-47/src/main` has two changed files under it
- **When** the folder is selected and staged
- **Then** `git add src/main` runs in `svc-47`
- **And** nothing is staged in the superproject

#### Scenario: a selection spanning three repositories

- **Given** folders selected under `svc-3`, `svc-47` and the superproject
- **When** they are staged
- **Then** three commands run, one per repository, each with its own paths

### Requirement: A folder says how much of it is on this side of the index

A folder SHALL say how much of it is on this side of the index.

Git has no half-staged directory — it does not track directories at all — so a
folder row says so itself. It carries the number of changes under it on its own
side of the index, and when some of what changed under it is on the other side
it reads `4 of 6` instead of `6`, in the colour a modified file is written in,
with the whole of it in words on the tooltip.

Changes are counted rather than paths. A file staged and then edited again is
one path in both lists, and counting paths would call its folder whole while a
commit would leave the second edit behind.

#### Scenario: four of six staged

- **Given** six files have changed under `Sources`, four of them staged
- **When** the commit view is opened
- **Then** `Sources` reads `4 of 6` under Staged and `2 of 6` under Unstaged

#### Scenario: a file staged and then edited again

- **Given** the only change under `Sources` is a file staged and then edited
- **Then** `Sources` reads `1 of 2` in both lists

### Requirement: The commit view keeps its place while files are written

The commit view SHALL keep its place while files are written.

The trees are rebuilt whenever the working copy changes, which is on every
filesystem event. A folder folded shut by hand stays shut across a rebuild, one
folded open stays open, and what is inside a folder opened again by hand comes
back as it was. The selection is carried across by path.

Staging takes rows away — a folder with nothing left under it stops being a row
— so when everything that was selected has gone the selection lands on the
nearest row above where it was, rather than nowhere.

#### Scenario: a file is saved while a folder is folded shut

- **Given** `Sources/AbydosKit` has been folded shut in the unstaged tree
- **When** something else is staged and the tree is built again
- **Then** `Sources/AbydosKit` is still shut and everything else is still open

#### Scenario: the selected folder is staged away

- **Given** a folder is selected in the unstaged tree
- **When** it is staged, and nothing under it is left unstaged
- **Then** the selection is on the row that was above it

### Requirement: One question answers which branch the work tree is on

One question SHALL answer which branch the work tree is on.

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

#### Scenario: a repository with nothing committed yet

- **Given** a repository created with `git init -b main` and no commit made
- **When** the branch is asked for
- **Then** it is `main`, and it is known to have nothing on it

#### Scenario: a commit checked out directly

- **Given** the work tree is on a detached HEAD
- **When** the branch is asked for
- **Then** there is no branch name

### Requirement: A branch with no commits on it shows, quietly

A branch with no commits on it SHALL show, quietly.

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

#### Scenario: the titlebar of a freshly created repository

- **Given** a project whose repository has no commits
- **When** the window opens
- **Then** the titlebar reads the branch's name, dimmed
- **And** its tooltip says there are no commits yet

### Requirement: Push says which branch it cannot send

Push SHALL say which branch it cannot send.

A branch with nothing committed on it cannot be pushed — there is no ref to
send, and `git push -u origin main` fails. The button is disabled, and it says
which branch is empty rather than offering the generic "Push this branch" that
a repository with no branch at all gets.

Amending is off for the same reason and is spelt out the same way: there has to
be a commit to amend, and the checkbox is disabled with a tooltip saying so
rather than letting git's `fatal: You have nothing to amend` reach the screen.

#### Scenario: a repository with a remote and no commits

- **Given** a repository with an `origin` and nothing committed
- **When** the commit page is opened
- **Then** the push button is disabled and reads `Push`
- **And** its tooltip names the branch and says it has no commits yet
- **And** the Amend checkbox is disabled

### Requirement: The titlebar says which checkout, and opens the others

The titlebar SHALL say which checkout, and SHALL open the others.

A repository with more than one worktree carries a control in the titlebar,
beside the name of the project: which checkout this window is looking at, and a
menu of every other one. A repository with a single checkout carries nothing —
there is no choice to offer, and a control explaining that would be furniture.

It qualifies the project rather than replacing it. A worktree of `abydos` is
still `abydos`, so the window goes on being named after the repository and the
control says which of its directories.

#### Scenario: the checkout the repository was cloned into

- **Given** a repository with three worktrees
- **When** the window is opened at the original checkout
- **Then** the titlebar has a worktree control
- **And** it draws an icon and a chevron with no words, because the project's
  name is already beside it

#### Scenario: a worktree named after the branch it holds

- **Given** a worktree at `abydos-backlog-0490-worktrees` on branch
  `backlog/0490-worktrees-chosen-from-the-titlebar`
- **When** the window is opened there
- **Then** the control draws no words either, because the titlebar is already
  showing that branch

#### Scenario: a worktree somebody gave a name of its own

- **Given** a worktree at `fixture-hotfix` on branch `release/2.1`
- **When** the window is opened there
- **Then** the control reads `hotfix`, which is the one thing the titlebar does
  not otherwise say

#### Scenario: a repository with one checkout

- **Given** a repository nobody has added a worktree to
- **When** the window is opened on it
- **Then** there is no worktree control at all

### Requirement: Choosing a checkout opens it as a project

Choosing a checkout SHALL open it as a project.

A worktree is a project in its own right — a different directory, with its own
files, its own git and its own language servers — so choosing one from the
titlebar opens it the way the project switcher opens a project, and not the way
a subproject narrows the scope of this one.

Which means: a checkout already open in another window is raised rather than
opened a second time, and otherwise the window is reused or a new one made
according to the same setting every other way of opening a project obeys. Two
windows on two checkouts of one repository is an arrangement somebody can keep.

Every way in agrees — the titlebar, the backlog card, the branches pane and the
project switcher all open a worktree through the one door.

#### Scenario: a checkout that is already open

- **Given** one window on the original checkout and another on a worktree
- **When** the worktree is chosen from the first window's titlebar
- **Then** the second window is raised
- **And** the first window is left on the checkout it was showing

#### Scenario: a checkout that is not open

- **Given** a window on the original checkout, and the setting to open projects
  in the window they were chosen from
- **When** a worktree is chosen from the titlebar
- **Then** that window moves to the worktree, keeping what each project had open

### Requirement: A list of checkouts is ordered, capped and honest

A list of checkouts SHALL be ordered, capped and honest.

The menu lists the repository's checkouts with the current one ticked. It is
usable on a repository that has seventy-five of them:

- The original checkout is first and always present, because it is the way back.
- The rest follow, most recently worked on first, estimated from the mtimes of
  each checkout's git metadata rather than by running git once per checkout.
- Ten are shown; any beyond that go into a submenu, and the current one is shown
  whether or not it fell past the cap.
- A worktree whose directory has been deleted is left out, since the only thing
  the menu could do with it is fail.
- The last entry opens the branches view, where every checkout is listed with a
  filter and can be added, removed and revealed.

Each entry says what is checked out there, in the three states a head can be in:
a branch, a branch with nothing committed on it, or a commit checked out
directly. It says the directory as well when the directory says something the
branch does not — the repository's own name is dropped from the front of it, and
when either name contains the other only the shorter is shown.

#### Scenario: a repository with seventy-five checkouts

- **When** the worktree menu is opened
- **Then** the original checkout is the first entry
- **And** ten entries are shown before a submenu holding the remaining
  sixty-five

#### Scenario: a checkout with no branch

- **Given** a worktree at `fixture-spike` with a detached head at `404fde9`
- **Then** its entry reads `spike — detached at 404fde9`

#### Scenario: a checkout with nothing committed on its branch

- **Given** a worktree made with `git worktree add --orphan` called
  `fixture-fresh`
- **Then** its entry reads `fresh — fixture-fresh — no commits yet`

#### Scenario: a checkout whose directory was made from its branch

- **Given** a worktree at `fixture-feature-login` on branch `feature/login`
- **Then** its entry reads `feature/login`, and does not say the directory as
  well

### Requirement: A checkout is dated by the metadata that moves

A checkout SHALL be dated by the metadata that moves.

How recently a checkout was worked on is read from the mtimes of its git
metadata — the files a commit, a checkout or a `git status` rewrites.

A linked worktree keeps none of that in its own directory: its `.git` is a
one-line pointer written when the worktree was made and never touched again, and
everything that moves lives at the far end of it. The pointer is followed, so a
worktree committed in this morning is more recent than one made in March and
abandoned. This is what orders the worktree menu and the project switcher's list
of checkouts alike.

#### Scenario: a worktree made months ago and worked in today

- **Given** two worktrees created in the same minute
- **When** one of them has been committed in since
- **Then** it is the more recent of the two

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

### Requirement: Discard says how much it takes, and which of it is deleted

Discard SHALL say how much it takes, and which of it is deleted.

Discard is the one thing this pane does that has no way back, so it asks first,
and both the menu entry and the confirmation carry the numbers.

A folder says how many files it is about to take, the way Stage and Unstage
already do. Where some of them are untracked it says how many, because those are
two different losses on one gesture: a tracked file goes back to the version in
the index, and an untracked file is deleted from the disk, with no git object
left anywhere. Where *everything* covered is untracked the verb changes — over a
file git has never seen, "Discard Changes" is false, since there are no changes,
there is a file, and it is about to stop existing.

The confirmation names stash, which is discard with a way back and is already in
the same menu. Ignored files are not touched: `clean` is asked for `-fd` and
never `-x`, so discarding a folder does not also take the build output somebody's
`.gitignore` keeps out of the way.

#### Scenario: a folder holding both kinds

- **Given** `Sources` has 40 changed files under it, 12 of them untracked
- **When** the menu is opened on the folder
- **Then** the entry reads `Discard Changes in “Sources” (40 files, 12 untracked)…`
- **And** the confirmation says the 12 are deleted from the disk and the other 28
  go back to the version in the index
- **And** it says the change cannot be undone, and names stash

#### Scenario: a file git has never seen

- **Given** an untracked file `new.swift`
- **When** the menu is opened on it
- **Then** the entry reads `Delete “new.swift”…` and the button reads `Delete`

#### Scenario: a folder with something ignored under it

- **Given** a folder holding a changed file and a file matched by `.gitignore`
- **When** the folder's changes are discarded
- **Then** the ignored file is still there

### Requirement: A discard only restores the paths git tracks something under

A discard SHALL only restore the paths git tracks something under.

The paths a discard was asked for go to `git clean` as they are, and then to
`git checkout` only if git has something tracked under them.

Git validates every pathspec before it restores anything, so one path with
nothing tracked under it — an untracked file, or a folder holding only untracked
files — fails the whole restore with *"pathspec did not match any file(s) known
to git"*. Handing over both meant deleting the untracked half of a selection and
then reverting none of the rest, and reporting git's error for an operation that
had already destroyed something. Which paths those are is one `git ls-files` for
all of them, and the answer only decides which of the original paths to pass on:
a folder is still one argument, not the forty files beneath it.

#### Scenario: a selection holding one modified and one untracked file

- **Given** `tracked.txt` is modified and `new.txt` is untracked
- **When** both are discarded together
- **Then** `new.txt` is gone from the disk
- **And** `tracked.txt` holds what the index holds for it
- **And** nothing is reported as having gone wrong

#### Scenario: a folder holding nothing but untracked files

- **When** it is discarded
- **Then** the folder is gone, and git is not asked to restore it

### Requirement: A branch another checkout holds offers that checkout

A switch to a branch that another checkout already has SHALL offer that checkout
rather than reporting git's refusal and stopping.

git refuses it, correctly and uselessly:

    fatal: 'ui' is already used by worktree at '/…/agent-a9b22c96f3f4d82eb'

Every word of that is true and none of it helps. The branch *is* checked out,
somewhere this program can open, and the thing somebody wanted is one press away.

**Which checkout holds the branch SHALL be asked of the worktree list, not read
out of the message.** `git worktree list` states it as a fact; the sentence above
is one version of one program's phrasing, and matching against it is the mistake
already named for `No such module`. It also means no path is ever parsed out of
prose, which is where a name with a space or a quote in it goes wrong.

**The offer SHALL open the checkout through the one door every other way of
choosing one uses**, so a window already showing that checkout is raised rather
than a second one made — the behaviour *Choosing a checkout opens it as a
project* already promises.

**Nothing SHALL happen without being asked for.** Opening another checkout moves
somebody's window; the offer says what it will do and waits. And the branch SHALL
NOT be taken from the checkout that holds it — no force, no move, no detaching
the other one. Somebody who wants to look at a branch is not asking to rearrange
their repository.

**The checkout SHALL be named as what it is.** The original clone holding a
branch reads differently from a directory under `.claude/worktrees`, and the list
already tells them apart.

**Every other refusal SHALL be reported exactly as it is now.** A dirty work
tree, a branch that does not exist, a hook that said no: git's own message is the
clearest available explanation, and an offer that appeared for those would be one
more sentence people learn to ignore.

#### Scenario: a branch a worktree has

- **GIVEN** a repository whose worktree at `.claude/worktrees/agent-a9b2` has the
  branch `ui`
- **WHEN** `ui` is chosen from the titlebar of the main checkout
- **THEN** it is not switched to, and the window offers to open that checkout
- **AND** taking the offer opens it the way choosing a checkout does

#### Scenario: the offer is declined

- **GIVEN** the same offer, unpressed
- **THEN** nothing has moved, and the notification carries git's own message

#### Scenario: a branch the main checkout has

- **GIVEN** a window on a worktree, and `main` checked out in the original clone
- **WHEN** `main` is chosen
- **THEN** the offer names the main checkout rather than a path under
  `.claude/worktrees`

#### Scenario: a dirty work tree

- **GIVEN** uncommitted changes that a switch would overwrite
- **WHEN** another branch is chosen
- **THEN** git's refusal is shown as it is today, and no checkout is offered

#### Scenario: every way in agrees

- **GIVEN** the same held branch
- **WHEN** it is chosen from the branches pane, or typed into the project
  switcher
- **THEN** the same offer is made as from the titlebar

### Requirement: A checkout that is registered and not there is offered a prune

A checkout that is registered and not there SHALL be offered a prune rather than
an open.

A worktree deleted with `rm -rf` stays in the repository's list, and git goes on
refusing the branch on behalf of a directory that does not exist. Offering to open
it would fail, and the sentence would be the second useless thing somebody was
told in a row.

**The switch SHALL NOT be retried on its own after pruning.** A prune changes the
repository; doing two things from one press is one more than was agreed to.

#### Scenario: a worktree somebody deleted by hand

- **GIVEN** a branch held by a registered worktree whose directory is gone
- **WHEN** that branch is chosen
- **THEN** the offer is to remove the stale registration, and says the directory
  is missing
- **AND** taking it prunes, and does not switch

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

**Deleting one SHALL be asked for on the tag itself**, from the row's own menu
and from the keyboard, for one selected tag or several — and only where every
selected row is a tag, since a branch delete is a different question with a
different sheet. The sheet SHALL name the tags it is about to remove and where
each one points, so that what is being agreed to can be checked against what
was selected.

#### Scenario: pointing a moving tag at a branch

- **GIVEN** a tag `v1` and a branch `main`
- **WHEN** the tag's move sheet is opened and `main` chosen
- **THEN** the commit and subject `main` resolves to are shown before agreeing
- **AND** agreeing points `v1` there and says what it left, and where

#### Scenario: deleting a tag from its row

- **GIVEN** the tag `v0.9` in the tags section
- **WHEN** its delete is chosen and agreed to
- **THEN** `v0.9` is gone from the repository and from the tree

#### Scenario: the sheet says what it is about to remove

- **GIVEN** two tags selected
- **WHEN** the delete sheet opens
- **THEN** it names both tags and what each points at

#### Scenario: a selection that is not all tags

- **GIVEN** a branch row and a tag row selected together
- **THEN** the tag delete is shown disabled rather than acting on half the selection

### Requirement: The numbers on a changes row are drawn in columns

The added count, the removed count and a folder's file tally SHALL each be drawn
right-aligned on one x for the whole of that side, not on the trailing edge of
their own row.

Every row put its text hard against the trailing inset, so a folder — which has
a tally after its counts — pushed its `+69 −16` left by the width of that tally
and the file under it did not. Reading down a nested tree, the plus signs
stepped in and out by a digit at every level, which is the one thing a column of
numbers exists not to do.

The columns SHALL be as wide as the widest value on that side, so a `+1234`
somewhere in the tree does not overlap the row above it, and SHALL be measured
once per reload rather than once per row.

**The name gives way, as it already did.** A long path and `+1234 −567` do not
both fit in a sidebar, and of the two the name can be cut and still be
recognised. A file row now reserves the tally column it never draws in, which is
what alignment costs.

#### Scenario: a folder and the file under it

- **GIVEN** a folder whose only changed file is `BranchesPane.swift`
- **THEN** the folder's `+98` and the file's `+95` are drawn on the same x
- **AND** so are their removed counts

#### Scenario: a pane too narrow for both

- **GIVEN** the pane at 250 points and a deeply nested path
- **THEN** the columns hold and the name is what is cut

### Requirement: Staging answers the click at once

Staging or unstaging SHALL move the affected rows to their new side as soon
as the git command reports success, with the following status re-read
confirming or correcting; the rows SHALL NOT wait for the full refresh. A
stage that took seconds to show left somebody double-clicking again to be
sure the first one registered.

#### Scenario: a staged file switches sides in one step

- **GIVEN** an unstaged file double-clicked to stage
- **WHEN** `git add` returns success
- **THEN** the row is on the staged side before any status re-read completes

#### Scenario: the status remains the authority

- **GIVEN** a stage whose command succeeded for some paths and not others
- **WHEN** the following status read lands
- **THEN** the trees show what the status says, whatever moved optimistically

### Requirement: A refresh that arrives busy is kept

A refresh requested while the pane is mid-operation SHALL run after the
operation instead of being dropped. Dropping it meant a second double-click
during a stage vanished, and the trees waited for an unrelated event to
come true again.

#### Scenario: a change lands during a stage

- **GIVEN** a stage in flight
- **WHEN** a refresh is requested before it finishes
- **THEN** the trees re-read once the stage completes, without waiting for
  another event

### Requirement: The app's own writes do not re-walk the ignored files

The ignored-files walk — the expensive read over the whole work tree — SHALL
run when the ignore rules changed, and SHALL NOT be re-triggered by the
app's own index writes. Every stage was paying 0.8–1.6 s for it because the
repository object was rebuilt on each `.git` event, discarding the
fingerprint that existed to prevent exactly this.

#### Scenario: staging does not pay the walk

- **GIVEN** a repository with a large ignored build directory
- **WHEN** a file is staged and the watcher reports the index write
- **THEN** no ignored-files walk runs

#### Scenario: an edited ignore file still does

- **WHEN** a `.gitignore` is saved
- **THEN** the walk runs and the tree's ignored markings update

### Requirement: The diff render does not stand in front of the stage

The diff shown for a selected row SHALL NOT delay an immediately following
stage: the render is deferred past the double-click interval and cancelled
by the activation, so the second click of a double-click is not queued
behind a parse of a diff nobody kept.

#### Scenario: a double-click stages without rendering the diff first

- **GIVEN** a large changed file
- **WHEN** it is double-clicked to stage
- **THEN** the stage runs without a diff render preceding it

#### Scenario: a single click still shows the diff

- **WHEN** a row is clicked once
- **THEN** its diff appears after the deferral, as before

### Requirement: A checkout made for a pull request says that is what it is

A worktree this program created on a pull request's behalf SHALL be
distinguishable in the list of checkouts from one somebody made by name, and
SHALL be removable from where it was made.

The list of checkouts is a list of places somebody chose to work. A checkout
made to read somebody else's branch is a different kind of thing: it is
temporary, it belongs to a review rather than to a piece of work, and it will
accumulate — a repository whose reviewer opens three pull requests a day
otherwise grows a checkout a day, each named after a stranger's branch, and the
menu that was ordered, capped and honest becomes a list nobody reads.

Saying which ones those are is what makes them collectable. Removing one SHALL
obey the rule the branches pane already keeps: a checkout holding changes
refuses rather than discarding them, whoever made it.

#### Scenario: a checkout made for a review

- **GIVEN** a pull request whose branch has been checked out to read it
- **WHEN** the list of checkouts is opened
- **THEN** that one is shown as belonging to the pull request it was made for

#### Scenario: finishing with it

- **GIVEN** such a checkout with nothing modified in it
- **WHEN** it is finished with
- **THEN** it is removed, and the list of checkouts is shorter by one

#### Scenario: finishing with one that has been worked in

- **GIVEN** such a checkout with uncommitted changes in it
- **WHEN** it is finished with
- **THEN** it refuses, and says what is in it

### Requirement: The changes tree keeps its selection when a row is opened
Expanding a folder in the commit page's changes tree SHALL keep that folder selected, including when the folder is an untracked one drawn as a compacted chain.

#### Scenario: Opening an untracked folder with the keyboard
- **WHEN** an untracked folder row is selected in the changes tree and → is pressed
- **THEN** the folder opens, showing what is under it, and the folder row is still the selection

### Requirement: Staging keeps a usable selection
Staging or unstaging from the changes tree SHALL leave the selection on a row that still exists, so that the keyboard can carry on from where it was.

#### Scenario: Staging with the keyboard
- **WHEN** a file is staged from the changes tree
- **THEN** the selection lands on the neighbouring row rather than being lost, and ↑ and ↓ move from it

### Requirement: Deleting a tag on the remote is agreed to separately

The delete sheet SHALL offer removing the tag from the remote as a choice of
its own, named after the remote — *Also delete on `origin`* — off by default,
and shown only where the repository has a remote. Locally a tag can be written
again from any commit that still exists; on the remote it is what a workflow,
a release page and everybody else's fetch reads, and the two SHALL NOT be one
agreement.

The local delete SHALL be run first, and the outcome SHALL be reported per
half: a tag gone here and still on the remote SHALL be said in those words
rather than as one failure, so nobody has to go to a terminal to find out
which state they are in. Deleting several tags SHALL NOT stop at the first
remote failure, the tags being independent of one another.

#### Scenario: local only, by default

- **GIVEN** the delete sheet open on `v0.9` in a repository with an `origin`
- **WHEN** it is agreed to without changing anything
- **THEN** the tag is deleted here and `origin` is not pushed to

#### Scenario: the remote half, asked for

- **GIVEN** the same sheet with *Also delete on `origin`* ticked
- **WHEN** it is agreed to
- **THEN** the tag is gone from this repository and from `origin`

#### Scenario: the remote refuses

- **GIVEN** a tag `origin` will not let go of
- **WHEN** the delete is agreed to with the remote ticked
- **THEN** what is said is that the tag is deleted here and still on `origin`, and why

#### Scenario: no remote to offer

- **GIVEN** a repository with no remotes
- **WHEN** the delete sheet opens
- **THEN** it offers no remote choice at all

