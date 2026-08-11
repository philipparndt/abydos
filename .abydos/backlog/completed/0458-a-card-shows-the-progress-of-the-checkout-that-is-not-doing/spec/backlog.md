<!-- What this item changes about `backlog`. Folded into
     .abydos/backlog/spec/backlog.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       The backlog has a button on the left rail
       A card offers the worktree its item is being worked on in
       A project with no backlog is offered one
       An item filed from the pane lands in open
-->

## ADDED Requirement: A card's progress is the worktree's, and says so

An item picked up with `start` is worked on in a checkout of its own, and the
checklist, the estimate, the pictures and the spec delta are all written there.
So a card reads those four from that checkout — found by number, because an
agent that has run `done` has moved its copy to `completed/` on the branch while
the project still has it in `in-progress/`. Where the item *stands* stays the
project's answer: the folder it is in is what says who is working on what, and
work finished on a branch nobody has merged is not finished here.

The card says which copy it is showing, because a fraction from a branch three
commits ahead is not the same fact as one from the project. Where a checkout is
recorded and gone, the project's copy is all there is, and the card says that
too rather than passing an old number off as a current one.

Read when the folder is walked and not while drawing: a board redraws on every
scroll, and a fraction that costs a file open is a fraction that cannot be on a
card.

### Scenario: an agent has ticked three of six on its branch

- **Given** an item in `in-progress/` whose worktree's copy has three of six
  steps ticked, and whose copy in the project has none
- **Then** its card reads `3/6 in the worktree`, and the item stays in the
  in-progress column

### Scenario: the agent has finished and the branch is not merged

- **Given** an item whose worktree's copy has been moved to `completed/` by
  `done`, while the project's copy is still in `in-progress/`
- **Then** the card is still in the in-progress column, and still shows the
  branch's fraction — the copy is found by number, not by where it sits

### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **Then** the fraction is the project's copy and the card says `0/6 in the
  project`

## MODIFIED Requirement: A card offers the worktree its item is being worked on in

An item picked up with `start` is being worked on in a checkout somewhere on
this machine, and the card that draws that branch also offers three things to do
with it: open it as a project of its own, open a shell in that directory, and
reveal it in Finder — for when what somebody wants is the files rather than the
project or a terminal. All three are offered only while the checkout is still
there — a worktree somebody removed by hand leaves the recorded run behind, and
neither the branch on the card nor the three menu entries appear for it.

### Scenario: an item being worked on

- **Given** a card for an item whose worktree exists
- **When** its menu is opened
- **Then** it offers to open the worktree as a project, to open a terminal in
  it, and to reveal it in Finder

### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **When** its menu is opened
- **Then** none of the three is offered, and the card does not draw the branch

## ADDED Requirement: An item says how much longer it has

An item carries an estimate of how much work is left, written by whoever is
doing it, as one line under `## Estimate` with the time it was judged in front
of it. Nothing derives it from the clock and the checklist: steps are not the
same size, and elapsed time over steps ticked is most confident exactly when it
is most wrong. An item nobody has estimated has no estimate, which is a
different thing from an estimate of nothing.

The time is part of the claim, so a line without one is not an estimate and does
not parse — which is what lets the template carry a line of prose under the
heading saying what to write there. A card shows the estimate beside the
fraction, with the time it was said rather than how long ago, because a card is
drawn for as long as nothing changes and a relative age would freeze at the
moment the board was built.

### Scenario: an agent revising its estimate

- **Given** an item being worked on
- **When** `abydos-backlog eta 458 "about an hour left"` is run
- **Then** the item's `## Estimate` says that and the time it was said, any
  earlier estimate is replaced, and its card shows `about an hour left, as of
  14:20`

### Scenario: nobody has said

- **Given** an item straight from the template, whose `## Estimate` holds only
  the line of prose saying what to write there
- **Then** it has no estimate, and its card shows none
