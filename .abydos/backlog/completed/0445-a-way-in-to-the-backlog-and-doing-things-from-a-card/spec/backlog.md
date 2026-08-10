<!-- What this item changes about `backlog`. Folded into
     .abydos/backlog/spec/backlog.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     Nothing has been said about backlog yet, so this is all ADDED.
-->

## ADDED Requirement: The backlog has a button on the left rail

The strip down the left edge of the window carries a button that shows the
backlog, first in the group at the bottom where the panes that dock below the
editor live. It is the same thing ⇧⌘B and Agent ▸ Backlog do.

### Scenario: a window on a project

- **Given** a window with no backlog pane open
- **When** the checklist button at the bottom of the left rail is pressed
- **Then** the panel opens showing the backlog, board or list, whichever was
  last chosen

## ADDED Requirement: A card offers the worktree its item is being worked on in

An item picked up with `start` is being worked on in a checkout somewhere on
this machine, and the card that draws that branch also offers to open it: as a
project of its own, and as a shell in that directory. Both are offered only
while the checkout is still there — a worktree somebody removed by hand leaves
the recorded run behind, and neither the branch on the card nor the two menu
entries appear for it.

### Scenario: an item being worked on

- **Given** a card for an item whose worktree exists
- **When** its menu is opened
- **Then** it offers to open the worktree as a project and to open a terminal
  in it

### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **When** its menu is opened
- **Then** neither entry is offered, and the card does not draw the branch

## ADDED Requirement: A project with no backlog is offered one

Where there is no `.abydos/backlog`, the pane says so rather than drawing an
empty board, and offers to make one — through the same code `abydos-backlog
init` runs, for the assistants installed on this machine. Once it is made the
pane shows the board without being reopened, and opens the workflow document,
which is what `init` on the command line says to read next.

### Scenario: opening the backlog in a project that has none

- **Given** a project with no `.abydos/backlog`
- **When** the backlog is shown
- **Then** it says the project has no backlog and offers to make one, and names
  `abydos-backlog init` as the same thing from a terminal

### Scenario: making one

- **Given** that offer, agreed to
- **Then** the state folders, the workflow, `project.md`, the spec and the
  instruction files are written, and the pane shows the board over them

## ADDED Requirement: An item filed from the pane lands in open

The pane files a new item by asking for a title and nothing else. It lands in
`open/` with the next number and the template, and is opened so it can be
filled in. There is no control anywhere in the pane that files one into
`ready/`: `ready` is the promise that the deciding is done, and it is made by
moving an item there, which is a person's decision and not a button's.

### Scenario: filing one from the board

- **Given** a backlog whose highest number is 445
- **When** a new item is filed from the pane
- **Then** it is `open/0446-…`, `ready/` is unchanged, and the new item is open
  in the editor
