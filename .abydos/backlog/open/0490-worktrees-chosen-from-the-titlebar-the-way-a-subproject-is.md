# 490. Worktrees chosen from the titlebar, the way a subproject is

> working trees shall be selectable in the title bar like subprojects. I think
> sometimes we already show working trees there but not for the current project

**Both halves of that are right, and the second one explains the first.**
`MainWindowController.readWorktree()` asks `GitWorktrees.list(in:)` for every checkout
and then keeps only the one *containing this window's root*:

    guard let containing, !containing.isPrimary, …
    else { self.capsule?.setWorktree(nil); … }

So the chip appears when the window is opened **at** a worktree, and never when it is
opened at the primary checkout. Opening `~/dev/abydos` shows `abydos | main` and
nothing else, which is the screenshot. The information is already in hand — the call
lists them all, with `isPrimary` and a `name` each — and all but one is thrown away.

## What exists to build on, and it is nearly everything

- **`GitWorktrees.list(in:)`** returns every worktree with its path, name and whether
  it is primary. Already async, already used, already parsing `--porcelain`.
- **`TitlebarCapsule.setWorktree(_:)`** already draws the chip and already has the
  right doctrine written into it: *"a worktree of ideai is still ideai, and a titlebar
  that said `titlebar-capsule` would be naming a directory rather than the thing being
  worked on"*. The name stays the repository's; the chip qualifies it.
- **`SubprojectPillButton`** is the pattern being asked for, complete: a pill with
  `onClick` opening a menu, `onLeave` to go back, a `menuFormRepresentation` for when
  the toolbar overflows, and `visibilityPriority = .low` so it is the first thing to
  collapse. A worktree pill is that again with a different list behind it.
- **`ProjectSwitcherPopover`** already knows about worktrees for its own purposes
  (there is a comment about a worktree being the worktree rather than the repository it
  came from), so whatever it decided is worth reading before deciding differently.

## What has to be decided

- **Where it goes: the capsule's chip, or a pill of its own?** The chip is a *label*
  today and the subproject is a *pill* — a control. Making the existing chip clickable
  is less furniture in a crowded titlebar; a separate pill matches the thing the report
  asks to be "like". Whichever, there is already a branch name, a subproject pill, a
  devcontainer pill and a run control up there, and they collapse by priority.
- **What switching actually means.** A subproject narrows the *scope* inside one
  checkout. A worktree is a **different directory on disk**, so choosing one is closer
  to opening a project: the tree, git, the language servers and the terminal's working
  directory all move. Does it reuse the window, like a subproject, or open one, like a
  project? Reusing means tearing down and rebuilding almost everything the window
  holds, and 0454 established that a card's work happens in a worktree *while another
  window is on the primary checkout* — so two windows on two checkouts is a real and
  wanted arrangement.
- **Whether the primary is in the list.** It must be, or there is no way back — and
  `readWorktree` currently treats "primary" as "nothing to say", so it has no name to
  show for it. `GitWorktrees` has one.
- **What a worktree with no branch, or a detached one, reads as.** 0477 taught this
  lesson once already: an unborn or detached HEAD is a state the titlebar has to be
  honest about, and a worktree list will contain both.
- **Whether the backlog's worktrees are special.** `abydos-backlog start` makes them
  under a predictable name per item, and the backlog pane already reveals them (0454).
  A list that shows `0489-a-truecolour-cell-costs-a-microsecond` beside `main` is
  useful; one that shows fifteen of them is a menu nobody reads. Whether stale ones are
  pruned, or ordered by mtime, or grouped, is a judgement — and `abydos-backlog runs
  prune` already exists for the pruning half.

## Worth knowing

Nothing here needs git beyond what is already called, so the cost is a menu and a
switch rather than new machinery. The risk is not in listing them — it is in what
"switch" tears down, which is why that decision belongs before any of the drawing.

## Steps

- [ ] `readWorktree` keeps the whole list rather than the one containing the window
- [ ] Decide: the chip becomes a control, or a pill of its own — and say why
- [ ] Decide what switching does — reuse the window or open one — against the fact
      that two windows on two checkouts is a wanted arrangement
- [ ] The primary checkout is in the list and named, so there is a way back
- [ ] A detached or unborn worktree reads honestly, the way 0477 settled for branches
- [ ] Decide what to do about many backlog worktrees, and say what was chosen
- [ ] Watch it on this repository, which has several worktrees at once
- [ ] Write down here what was ruled out on the way
- [ ] `spec/<capability>.md` says what the project now does
