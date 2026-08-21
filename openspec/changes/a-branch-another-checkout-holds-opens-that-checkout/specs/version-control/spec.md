## ADDED Requirements

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
