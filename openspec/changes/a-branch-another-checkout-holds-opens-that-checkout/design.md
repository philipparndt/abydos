## Context

`git checkout ui` in a repository where another worktree has `ui` exits non-zero
with

    fatal: 'ui' is already used by worktree at '/…/agent-a9b22c96f3f4d82eb'

and the app shows that, because git's message is usually the best explanation
available — a dirty work tree, a missing branch, a hook that refused. This one is
the exception: the app can act on it, and does not.

What exists to build on:

- `GitWorktrees.list(in:)` answers `git worktree list --porcelain` as
  `[GitWorktree]`, each with the `branch` it holds, whether it `isMissing`, and
  whether it `isPrimary`.
- `GitWorktrees.prune(in:)` runs `git worktree prune`.
- **"Choosing a checkout opens it as a project"** — a requirement, with one door
  behind the titlebar, the backlog card, the branches pane and the switcher: a
  window already on that checkout is raised, otherwise the setting decides
  whether this window moves or a new one opens.
- `Toast` carries an `actionTitle` and an action, so an offer is a notification
  with a button rather than a dialog.

Two callers run a checkout: `BranchMenu.checkout(_:in:)`, shared by the titlebar
menu and the project switcher, and `BranchesPane.checkoutSelected()`.

## Goals / Non-Goals

**Goals:**

- A branch held by another checkout leads somebody to that checkout.
- A stale registration is told apart from a live worktree, and offered something
  that works.
- Every other refusal keeps saying exactly what it says now.
- Every way of switching branches behaves the same.

**Non-Goals:**

- Rearranging the repository: moving a worktree, or taking a branch off one.
- A dialog. This is a notification with an action, like every other refusal the
  app can do something about.
- Guessing at the *reason* for any other non-zero exit.

## Decisions

**Try, then explain.** The lookup runs only after a checkout has failed, so the
common case — a switch that works — costs nothing extra, and the rare one costs
a `git worktree list`. The alternative, checking before every switch, pays in the
common case for the rare one and still cannot be trusted: git is the authority at
the moment it runs, and a worktree can appear between a check and a checkout.

**The worktree list decides, not the message.** `git worktree list --porcelain`
says which checkout holds which branch as a fact. Matching `already used by
worktree` would be reading one version of one program's wording — the same
mistake `DiagnosticWeight` names for `No such module`, and the same answer:
**ask the thing that knows.** It also means the app never has to parse a path out
of a sentence, which is where quoting and spaces go wrong.

**The offer is the door that already exists.** Opening the checkout goes through
the one that the titlebar, the backlog card, the branches pane and the switcher
use, so a window already showing that checkout is raised rather than a second one
made — which is the behaviour `version-control` already promises and the whole
reason not to write a second way.

**A missing worktree is offered a prune, not an open.** `rm -rf` on a worktree
leaves it registered, and git refuses the branch on behalf of a directory that is
not there. "Open it" would fail, and the sentence would be the second useless
thing somebody was told. `isMissing` is already on `GitWorktree`; the offer is
`git worktree prune`, after which the branch is free — and the switch is *not*
retried automatically, because a prune is a change to the repository and doing
two things from one button is one more than somebody agreed to.

**The primary checkout is named as itself.** If the branch is held by the
original clone rather than by a worktree, the sentence says so — "the main
checkout has it" reads differently from a path under `.claude/worktrees`, and
`isPrimary` already tells them apart.

**Nothing changes for any other refusal.** The lookup answers "no worktree holds
that branch" for a dirty tree or a bad name, and then git's own message is shown
exactly as today. That is deliberate: the offer must be provable to appear only
where it is true, or it becomes another sentence people learn to ignore.

**Ruled out: parsing the path from git's message.** It is right there in the
message and it is the wrong source. Beside the wording risk, a path with a quote
or a newline in it is unparseable in general and the worktree list has it exactly.

**Ruled out: taking the branch away from the other checkout** (`git worktree
move`, or checking it out here with `--force`, or detaching the other one).
Somebody who wants to look at `ui` is not asking to change where `ui` lives, and
a program that rearranges a repository to satisfy a menu click is one nobody
trusts with a menu click.

**Ruled out: doing it silently.** Opening the other checkout without being asked
would move somebody's window on the strength of a guess about what they meant.
The offer says what it will do and waits.

## Risks / Trade-offs

- **Two git calls on a failed switch** rather than one. → Only on failure, and
  `git worktree list` on a repository with seventy-five checkouts is one process
  and no network.
- **The branch may be held by a worktree the person cannot see** — another
  machine's, a directory they have no access to. → The path is in the sentence
  either way, and `isMissing` covers the common half of it.
- **An offer nobody wants**: somebody may have meant to force the switch. →
  Nothing is done without the button being pressed, and git's own message is
  still in the notification's detail.

## Open Questions

- **Whether the branches pane should mark branches another checkout holds**
  before anybody tries — it lists branches and worktrees in one place and has the
  information. That is a second feature, and this item is the refusal.
- **What to do when the branch is held by a locked worktree.** `isLocked` is
  known; whether it changes the offer is not obvious, since a locked worktree can
  still be opened.
