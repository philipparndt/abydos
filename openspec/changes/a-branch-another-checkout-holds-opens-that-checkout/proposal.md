## Why

**Switching to a branch another checkout holds shows git's refusal and stops
there.** Reported today, from a real repository:

    Could not switch to ui
    fatal: 'ui' is already used by worktree at
    '/Users/philipparndt/dev/cuttr/.claude/worktrees/agent-a9b22c96f3f4d82eb'

Everything in that sentence is true and none of it is useful. The branch is
checked out — *somewhere this app can open*. The thing somebody wanted, to be
looking at `ui`, is one click away and the window says nothing about it.

This is a refusal with a known answer, which is the kind this program is
supposed to turn into an offer. And the offer already exists: **"Choosing a
checkout opens it as a project"** is a requirement of `version-control`, with
the titlebar, the backlog card, the branches pane and the project switcher all
going through the one door. A branch that is held by a checkout is a reason to
use that door, not a reason to print `fatal:`.

No originating backlog item: the backlog was dropped on 2026-08-19 and this was
reported on 2026-08-20.

## What Changes

- **A checkout refused because another worktree holds the branch offers that
  worktree.** The offer opens it the way every other way of choosing a checkout
  does, so a window that already shows it is raised rather than a second one
  made.
- **Which worktree holds it is asked of git, not read out of the message.** `git
  worktree list` says which checkout has which branch as a fact; the wording of
  `fatal: 'ui' is already used by worktree at …` is one version of one program's
  phrasing, and matching on it is the mistake the preparing-server work already
  named.
- **A stale registration is offered a different thing.** A worktree deleted with
  `rm -rf` is still registered, and git refuses the branch on its behalf: the
  path in the message does not exist, so "open it" would be a lie. That case
  offers to prune the registration instead, after which the branch is free.
- **Every other refusal is unchanged.** A dirty work tree, a branch that does
  not exist, a hook that said no: git's own message is the clearest thing there
  is and it keeps being shown.
- **Not proposed: checking before switching.** Asking the worktree list before
  every checkout pays for the rare case in the common one, and git is the only
  authority at the moment it runs.
- **Not proposed: moving the branch.** `git worktree move`, or taking the branch
  off the other checkout, is somebody rearranging their repository — a different
  intention from wanting to look at a branch.

## Capabilities

### Modified Capabilities

- `version-control`: it says a checkout can be chosen and what choosing one
  does, and nothing about a switch that cannot happen because a checkout
  already holds the branch. That refusal, and what is offered instead of it, is
  the same subject.

## Impact

- `Sources/AbydosKit/Git/` — which checkout holds a branch, as a question about
  the worktree list rather than about a message.
- `Sources/AbydosApp/Titlebar/BranchMenu.swift` — where a checkout is run and
  its refusal reported, shared by the titlebar and the project switcher.
- `Sources/AbydosApp/Git/BranchesPane.swift` — the second way in, which must
  agree.
- `GitWorktrees.prune` and the door that opens a checkout, both reused.
