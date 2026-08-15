## ADDED Requirement: The titlebar says which checkout, and opens the others

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

## ADDED Requirement: Choosing a checkout opens it as a project

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

## ADDED Requirement: A list of checkouts is ordered, capped and honest

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

## ADDED Requirement: A checkout is dated by the metadata that moves

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
