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

## Requirement: The titlebar says which checkout, and opens the others

A repository with more than one worktree carries a control in the titlebar,
beside the name of the project: which checkout this window is looking at, and a
menu of every other one. A repository with a single checkout carries nothing —
there is no choice to offer, and a control explaining that would be furniture.

It qualifies the project rather than replacing it. A worktree of `abydos` is
still `abydos`, so the window goes on being named after the repository and the
control says which of its directories.

### Scenario: the checkout the repository was cloned into

- **Given** a repository with three worktrees
- **When** the window is opened at the original checkout
- **Then** the titlebar has a worktree control
- **And** it draws an icon and a chevron with no words, because the project's
  name is already beside it

### Scenario: a worktree named after the branch it holds

- **Given** a worktree at `abydos-backlog-0490-worktrees` on branch
  `backlog/0490-worktrees-chosen-from-the-titlebar`
- **When** the window is opened there
- **Then** the control draws no words either, because the titlebar is already
  showing that branch

### Scenario: a worktree somebody gave a name of its own

- **Given** a worktree at `fixture-hotfix` on branch `release/2.1`
- **When** the window is opened there
- **Then** the control reads `hotfix`, which is the one thing the titlebar does
  not otherwise say

### Scenario: a repository with one checkout

- **Given** a repository nobody has added a worktree to
- **When** the window is opened on it
- **Then** there is no worktree control at all

## Requirement: Choosing a checkout opens it as a project

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

### Scenario: a checkout that is already open

- **Given** one window on the original checkout and another on a worktree
- **When** the worktree is chosen from the first window's titlebar
- **Then** the second window is raised
- **And** the first window is left on the checkout it was showing

### Scenario: a checkout that is not open

- **Given** a window on the original checkout, and the setting to open projects
  in the window they were chosen from
- **When** a worktree is chosen from the titlebar
- **Then** that window moves to the worktree, keeping what each project had open

## Requirement: A list of checkouts is ordered, capped and honest

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

### Scenario: a repository with seventy-five checkouts

- **When** the worktree menu is opened
- **Then** the original checkout is the first entry
- **And** ten entries are shown before a submenu holding the remaining
  sixty-five

### Scenario: a checkout with no branch

- **Given** a worktree at `fixture-spike` with a detached head at `404fde9`
- **Then** its entry reads `spike — detached at 404fde9`

### Scenario: a checkout with nothing committed on its branch

- **Given** a worktree made with `git worktree add --orphan` called
  `fixture-fresh`
- **Then** its entry reads `fresh — fixture-fresh — no commits yet`

### Scenario: a checkout whose directory was made from its branch

- **Given** a worktree at `fixture-feature-login` on branch `feature/login`
- **Then** its entry reads `feature/login`, and does not say the directory as
  well

## Requirement: A checkout is dated by the metadata that moves

How recently a checkout was worked on is read from the mtimes of its git
metadata — the files a commit, a checkout or a `git status` rewrites.

A linked worktree keeps none of that in its own directory: its `.git` is a
one-line pointer written when the worktree was made and never touched again, and
everything that moves lives at the far end of it. The pointer is followed, so a
worktree committed in this morning is more recent than one made in March and
abandoned. This is what orders the worktree menu and the project switcher's list
of checkouts alike.

### Scenario: a worktree made months ago and worked in today

- **Given** two worktrees created in the same minute
- **When** one of them has been committed in since
- **Then** it is the more recent of the two
