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

## What switching means, decided before any of the drawing

**Opening, not reusing — and the app decided this already, twice, in writing.**

    // Through the delegate rather than `switchProject`, so a worktree
    // opened from a backlog card obeys the same rule as one opened from
    // the project switcher: this window or a new one, whichever the
    // setting says, and an already-open checkout is raised rather than
    // opened twice.
    bottomPanel.onOpenProject = { … open(projectAt: root, from: self) }
                                        MainWindowController.swift:664

and, in the branches pane, *"a worktree is opened rather than checked out: it is
already a checkout, which is the whole reason it exists"*, with its callback
commented *"a worktree is a project in its own right"*.

So this item does not get to make the decision fresh; it gets to make the
titlebar obey the one already made. `AppDelegate.open(projectAt:from:)` is the
door, and routing through it answers the 0454 worry exactly rather than
approximately:

- a worktree **already open in another window is raised**, not opened twice —
  which is the "a card's work happens in a worktree while another window sits on
  the primary" arrangement, preserved by the routing rather than by a rule about
  it;
- otherwise `Settings.opensProjectsInNewWindow` decides, so somebody who wants
  one window gets one and somebody who wants two gets two. Neither is hard-coded
  into a titlebar, which is the wrong place to hold that opinion.

Reusing the window unconditionally was rejected on the strength of the above: it
would be this one control disagreeing with the switcher, the backlog card and
the branches pane about what opening a checkout means.

**A fourth caller was out of line and is brought in.** `BranchesPane`'s
`onOpenWorktree` went straight to `switchProject(to:)`, so double-clicking a
worktree there took over the window whatever the setting said and opened a second
window on a checkout that already had one. It goes through the delegate now, with
the other three.

## Where the control went, and why the chip could not be it

**A pill of its own, and the capsule's chip is retired into it.**

The chip loses on one fact, and it is the reported bug: **the chip has nothing to
say on the primary checkout.** A control that is invisible in exactly the place it
is most needed — `~/dev/abydos`, where the report was written — is not a control.
To make the chip clickable you first have to invent a chip for the primary, and
every candidate is bad: `abydos [abydos]` is the name twice, `abydos [main]` says
the branch a divider away from the branch. Then it has to become a third hit
target inside a capsule whose own comment says *"it stays two hit targets"*.

The pill answers all of that and costs less furniture than it looks:

- **It is not there at all for an ordinary project.** One worktree means no pill,
  the rule the branches pane already keeps — *"a repository nobody has added a
  worktree to should not carry a section explaining that it has one"*. Nothing in
  anybody's titlebar changes unless they use worktrees.
- **On the primary it is an icon and a chevron, with no label**, which is the
  trade `DevContainerPillButton` made and argued at length: the capsule already
  said the project's name and `abydos` twice is noise. The sentence is on the
  tooltip.
- **On a linked worktree it says whatever the capsule has not.** This started as
  "the worktree's folder name" — the chip moved — and watching it said otherwise;
  see below. The doctrine the chip carried survives either way: the capsule says
  `abydos`, the pill says which checkout.
- `.low` priority so it collapses before the run control, and a
  `menuFormRepresentation` for when it does.

## What the menu does about seventy-four of them

The item guessed fifteen. `git worktree list` in this repository answers **74**:
about fifty `abydos-backlog-NNNN-…`, twenty `.claude/worktrees/agent-…` from an
agent harness, and one belonging to a directory that was renamed years ago.

- **Ordered by last activity, most recent first**, from
  `ProjectDiscovery.lastActivity(of:)` — already written, already stats rather
  than runs git *"because this list can run to hundreds"*, which turns out to be
  the literal case. Stale agent scratch checkouts sink on their own.
- **The primary is always first and always present**, so there is a way back
  whatever the ordering says, and the current one is always shown and ticked even
  when it would have fallen off the end.
- **Ten rows, then a `More…` submenu** with the rest in the same order. Ten is a
  menu somebody reads; 74 is a menu nobody does.
- **`Show All Worktrees…` at the bottom** opens the branches pane, which already
  lists them with a filter field and can add, remove and reveal them. The titlebar
  is for going somewhere; managing them has a home already.
- **Missing ones are left out.** `prunable` means the directory is gone, so the
  row's only possible action fails. They stay visible in the branches pane, where
  removing one is the point.

No pruning policy is invented here. Which worktrees deserve to exist is
`abydos-backlog runs prune`'s question, and a menu that hid checkouts on a
guess about their names would be answering it badly.

## What watching it changed, on this repository

Three things, and none of them was visible from the code.

**1. `lastActivity` was measuring the wrong file, so the ordering ordered
nothing.** Every one of the fifty backlog worktrees came back with the same date:
its `abydos-backlog start`. `ProjectDiscovery.lastActivity` knew a worktree's
`.git` is a file — there is a comment saying so — and stat'ed *that file*, which
is a one-line `gitdir:` pointer written at creation and never touched again.
Being the newest of the times considered, it drowned out every other one.
Everything that moves is at the far end of the pointer, in
`<the primary>/.git/worktrees/<name>/`. Following it is four lines and it is the
whole of why the ordering means anything — the project switcher's scan reads the
same helper, so its list was dated the same wrong way and is not any more.

**2. A row saying both names said the same thing twice, at 130 characters.**

    abydos-backlog-0479-toggle-comment-answers-to-a-key-nobody-asked-for-on-a
      — backlog/0479-toggle-comment-answers-to-a-key-nobody-asked-for-on-a

`suggestedPath` builds the directory *out of* the branch, so for every worktree
this app makes, one of the two names is the other. Two rules cut it: the
repository's name comes off the front of the folder (every row is a checkout of
the same repository, and the control that opened the menu has just said which),
and when either name contains the other the shorter one stands alone. That last
one works in both directions — it drops the folder for
`abydos-backlog-0479-…`, and it drops the *branch* for an agent harness's
`agent-a0644…` checked out on `worktree-agent-a0644…`. Titles are then capped at
52 characters, from the tail, because what tells these apart is the number at the
front.

**3. The pill fell into the toolbar's overflow on the window that most needed
it.** On `abydos-backlog-0490-worktrees` the capsule wants half the titlebar for
`abydos | backlog/0490-worktrees-chosen-from-the-titlebar`, and one more pill was
enough to tip the toolbar over — so `.low` did exactly what it is for and the
worktree control vanished behind `»`. The fix is the same rule as the menu's,
applied harder: **a titlebar says only what the capsule beside it has not.** The
branch is on screen a foot to the left, so a pill reading `backlog-0490-worktrees`
is 150 points spent on a word already there. It goes wordless, it fits, and the
run control comes back to the right-hand end where it belongs.

What is left is the case the pill exists for: a worktree somebody named
themselves. `fixture | release/2.1` with a pill reading `hotfix` — see
`images/a-worktree-somebody-named-says-its-name.png`.

Watched on this repository at 75 checkouts (`images/…-at-last.png` and
`…-nothing-twice.png`), and on a fixture built for the states this repository does
not have: a hand-named directory, a detached worktree, and `git worktree add
--orphan`, which turns out to be the one way a *linked* worktree can be on a
branch with nothing on it. The menu reads `hotfix — release/2.1`, `spike —
detached at 404fde9` and `fresh — fixture-fresh — no commits yet`.

## Ruled out

- **Making the existing chip clickable.** The argument is in full above; the
  short of it is that the chip is blank on the primary, which is where the
  report was written.
- **Reusing the window, the way a subproject does.** It would be this one
  control disagreeing with the switcher, the backlog card and the branches pane
  about what opening a checkout means, and it would break the arrangement 0454
  relies on by taking over the window sitting on the primary.
- **Grouping the backlog's worktrees into a section of their own.** It reads well
  on this repository and nowhere else: it needs the menu to know that
  `abydos-backlog-NNNN-…` is special, which is one app's convention leaking into
  a general git control. Last-activity ordering sinks the stale ones without
  knowing anything about what they are, and it works for somebody whose worktrees
  are called something else entirely.
- **Hiding the `.claude/worktrees/agent-…` checkouts.** Same objection, and worse:
  they are real checkouts somebody may want, and a control that silently omits
  twenty of seventy-five is lying about what the repository has. They sink to the
  bottom of `More…` on their own, which is the honest version of the same result.
- **Pruning from the menu.** `abydos-backlog runs prune` and the branches pane
  both do this already, with a confirmation. A titlebar menu is for going
  somewhere.
- **A filter field, the way the project switcher has one.** An `NSMenu` cannot be
  typed at, and building a popover for this would be a second project switcher.
  `Show All Worktrees…` reaches the branches pane, which has the filter field
  already and can add and remove them too.
- **Asking git for each worktree's last commit date.** Truer than an mtime and
  seventy-five subprocesses to sort a menu, in front of somebody who has just
  clicked. `lastActivity` is a stat and it was written for exactly this
  objection.
- **Listing worktrees whose directory is gone.** The only thing a row can do is
  open one, and that fails. They stay in the branches pane, where removing them
  is the point.
- **Rebuilding the list when the menu opens.** `readWorktree` has already run git
  for the pill, so a second listing at the moment of the click buys the same
  answer with a pause in front of it. The list is kept.

## Steps

- [x] Decide what switching does — reuse the window or open one — against the fact
      that two windows on two checkouts is a wanted arrangement
- [x] Decide: the chip becomes a control, or a pill of its own — and say why
- [x] Decide what to do about many backlog worktrees, and say what was chosen
- [x] `GitWorktree` says when a checkout's branch has no commits on it, with a test
- [x] `readWorktree` keeps the whole list rather than the one containing the window
- [x] `WorktreePillButton`, its overflow menu item and `.low` priority
- [x] The primary checkout is in the list and named, so there is a way back
- [x] A detached or unborn worktree reads honestly, the way 0477 settled for branches
- [x] Ordering, the cap and the way through to the branches pane
- [x] Choosing one goes through the delegate — and the branches pane does too
- [x] A capture flag that reads the pill and its menu, since neither photographs
- [x] Watch it on this repository, which has seventy-four worktrees at once
- [x] Write down here what was ruled out on the way
- [ ] `spec/version-control.md` says what the project now does

## Estimate

2026-08-15 11:42 — about forty minutes left — the spec and the suite
