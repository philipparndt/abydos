# Backlog

## Purpose

Everything left to do on a project lives in `.abydos/backlog/`, as markdown in
state folders. The app shows it in the bottom panel as a list and as a board,
`abydos-backlog` works it from a terminal, and an agent reads and moves the same
files: there is no database and no server, so the three of them cannot disagree
about what an item is or where it stands.

## Requirements

### Requirement: The backlog has a button on the left rail

The left rail SHALL carry a button that opens the backlog.

The strip down the left edge of the window carries a button that shows the
backlog, first in the group at the bottom where the panes that dock below the
editor live. It is the same thing ⇧⌘B and Agent ▸ Backlog do.

#### Scenario: a window on a project

- **Given** a window with no backlog pane open
- **When** the checklist button at the bottom of the left rail is pressed
- **Then** the panel opens showing the backlog, board or list, whichever was
  last chosen

### Requirement: A card offers the worktree its item is being worked on in

A card SHALL offer the worktree its item is being worked on in.

An item picked up with `start` is being worked on in a checkout somewhere on
this machine, and the card that draws that branch also offers three things to do
with it: open it as a project of its own, open a shell in that directory, and
reveal it in Finder — for when what somebody wants is the files rather than the
project or a terminal. All three are offered only while the checkout is still
there — a worktree somebody removed by hand leaves the recorded run behind, and
neither the branch on the card nor the three menu entries appear for it.

#### Scenario: an item being worked on

- **Given** a card for an item whose worktree exists
- **When** its menu is opened
- **Then** it offers to open the worktree as a project, to open a terminal in
  it, and to reveal it in Finder

#### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **When** its menu is opened
- **Then** none of the three is offered, and the card does not draw the branch

### Requirement: A project with no backlog is offered one

A project with no backlog SHALL be offered one.

Where there is no `.abydos/backlog`, the pane says so rather than drawing an
empty board, and offers to make one — through the same code `abydos-backlog
init` runs, for the assistants installed on this machine. Once it is made the
pane shows the board without being reopened, and opens the workflow document,
which is what `init` on the command line says to read next.

#### Scenario: opening the backlog in a project that has none

- **Given** a project with no `.abydos/backlog`
- **When** the backlog is shown
- **Then** it says the project has no backlog and offers to make one, and names
  `abydos-backlog init` as the same thing from a terminal

#### Scenario: making one

- **Given** that offer, agreed to
- **Then** the state folders, the workflow, `project.md`, the spec and the
  instruction files are written, and the pane shows the board over them

### Requirement: An item filed from the pane lands in open

An item filed from the pane SHALL land in `open`.

The pane files a new item by asking for a title and nothing else. It lands in
`open/` with the next number and the template, and is opened so it can be
filled in. There is no control anywhere in the pane that files one into
`ready/`: `ready` is the promise that the deciding is done, and it is made by
moving an item there, which is a person's decision and not a button's.

#### Scenario: filing one from the board

- **Given** a backlog whose highest number is 445
- **When** a new item is filed from the pane
- **Then** it is `open/0446-…`, `ready/` is unchanged, and the new item is open
  in the editor

### Requirement: A card's progress is the worktree's, and says so

A card's progress SHALL be the worktree's, and SHALL say so.

An item picked up with `start` is worked on in a checkout of its own, and the
checklist, the estimate, the pictures and the spec delta are all written there.
So a card reads those four from that checkout — found by number and not by path,
because the branch may have moved the item into another folder: an agent that
gets stuck moves its copy to `waiting/` while the project still has it in
`in-progress/`. Where the item *stands* stays the project's answer: the folder it
is in is what says who is working on what, and work finished on a branch nobody
has merged is not finished here.

The card says which copy it is showing, because a fraction from a branch three
commits ahead is not the same fact as one from the project. Where a checkout is
recorded and gone, the project's copy is all there is, and the card says that
too rather than passing an old number off as a current one.

Read when the folder is walked and not while drawing: a board redraws on every
scroll, and a fraction that costs a file open is a fraction that cannot be on a
card.

#### Scenario: an agent has ticked three of six on its branch

- **Given** an item in `in-progress/` whose worktree's copy has three of six
  steps ticked, and whose copy in the project has none
- **Then** its card reads `3/6 in the worktree`, and the item stays in the
  in-progress column

#### Scenario: the branch has parked the item and the project has not

- **Given** an item whose worktree's copy has been moved to `waiting/` on the
  branch, while the project's copy is still in `in-progress/`
- **Then** the card is still in the in-progress column, and still shows the
  branch's fraction — the copy is found by number, not by where it sits

#### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **Then** the fraction is the project's copy and the card says `0/6 in the
  project`

### Requirement: An item says how much longer it has

An item SHALL say how much longer it has.

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

#### Scenario: an agent revising its estimate

- **Given** an item being worked on
- **When** `abydos-backlog eta 458 "about an hour left"` is run
- **Then** the item's `## Estimate` says that and the time it was said, any
  earlier estimate is replaced, and its card shows `about an hour left, as of
  14:20`

#### Scenario: nobody has said

- **Given** an item straight from the template, whose `## Estimate` holds only
  the line of prose saying what to write there
- **Then** it has no estimate, and its card shows none

### Requirement: `abydos-backlog` works wherever it is run from

`abydos-backlog` SHALL work wherever it is run from.

The command ships in three places — inside the app at
`Abydos.app/Contents/Resources/bin/`, on the `PATH` after `make install-cli`,
and beside the binaries of a checkout — and every subcommand behaves the same in
all three. In particular it never fails for want of a resource it ships with:
where the app's resource bundles can be found, they are used; where they cannot,
whatever needed them falls back, and nothing aborts.

#### Scenario: the copy inside the app picks an item up

- **Given** `Abydos.app/Contents/Resources/bin/abydos-backlog`, whose own
  directory holds no resource bundles
- **When** `start <number>` is run on a ready item
- **Then** the worktree is made, the item moves to `in-progress/`, and the
  configured assistant is started in the worktree

#### Scenario: a copy with no resource bundles anywhere near it

- **Given** the command installed by `make install-cli`, in `/usr/local/bin`
- **When** `start <number>` is run
- **Then** it does the same thing, reading its settings without the shipped
  colour schemes rather than failing

### Requirement: A start that cannot launch an agent says where the work is

A start that cannot launch an agent SHALL say where the work is.

Half of `start` cannot be undone: by the time an agent could fail to launch, the
branch exists, the worktree exists, and the item has moved to `in-progress/` in
both checkouts. So the worktree and the branch are printed as soon as they
exist, before anything is asked of the assistant, and an agent that does not
start is followed by the directory to `cd` into and the prompt it would have
been given. An item that looks picked up and is not is the one outcome this
must not have.

#### Scenario: no assistant is installed

- **Given** a backlog configured for an assistant that is not on this machine
- **When** `start <number>` is run
- **Then** it prints the branch and the worktree, says nothing was started, and
  prints the directory and the prompt to hand to an agent by hand

#### Scenario: the assistant cannot be run

- **Given** a configured assistant whose binary refuses to start
- **When** `start <number>` is run
- **Then** the failure is reported, and the worktree and prompt are printed so
  the item can be picked up by hand

### Requirement: An item's state is the folder it is in

An item's state SHALL be the folder it is in.

Nothing records a state anywhere else. An item is in `open/`, `ready/`,
`in-progress/`, `waiting/`, `completed/` or `history/`, and moving it along
moves the file or the folder, keeping the number it was given.

#### Scenario: moving an item that carries screenshots

- **Given** `open/0443-something/` with `task.md` and two files in `images/`
- **When** it is moved to `ready`
- **Then** it is `ready/0443-something/` with both files still in it
- **And** it still answers to the number 443

#### Scenario: a number is given once

- **Given** a backlog whose highest number anywhere, `history/` included, is 442
- **When** a new item is written
- **Then** it is 443, and no existing item's number changes

### Requirement: An item is a file, or a folder when it carries something

An item SHALL be a file, or a folder when it carries something.

An entry in a state folder is an item if it is a `.md` file, or a directory
containing `task.md`. Both are read the same way: the same title, the same
number, the same checklist.

#### Scenario: attaching a file to an item that is one file

- **Given** `open/0443-something.md`
- **When** a screenshot is attached to 443
- **Then** it becomes `open/0443-something/task.md` with the screenshot in
  `images/`, and the markdown is unchanged

#### Scenario: two screenshots of the same name

- **Given** an item that already carries `Screenshot.png`
- **When** another file called `Screenshot.png` is attached
- **Then** both are kept, the second as `Screenshot-2.png`

### Requirement: Ready is the only folder an agent picks from

`ready` SHALL be the only folder an agent picks from.

`ready` means the deciding is done. Nothing moves an item into it
automatically, and picking one up is refused for an item in any other state.

#### Scenario: asking for the next thing to do

- **Given** items in `open/` and two in `ready/`, numbered 12 and 8
- **When** the next item is asked for
- **Then** it is 8, and nothing in `open/` is offered

### Requirement: An item is picked up into a worktree of its own

An item SHALL be picked up into a worktree of its own.

Starting an item makes a git worktree on `backlog/<number>-<slug>`, moves the
item to `in-progress/` in both the project and the worktree, records the run on
this machine, and starts the configured assistant there.

#### Scenario: an item that is not committed

- **Given** a ready item that has never been committed
- **When** it is started
- **Then** it is refused, and stays in `ready/`, because a worktree is a
  checkout of HEAD and would not contain the item

#### Scenario: an item already being worked on

- **Given** an item whose worktree exists
- **When** it is started again
- **Then** it is refused and names the worktree

### Requirement: The spec says what the project does, and items change it by delta

The spec SHALL say what the project does, and an item SHALL change it by delta.

`spec/` holds one file per capability. An item that changes behaviour carries
`spec/<capability>.md` in its own folder, with each requirement headed `ADDED`,
`MODIFIED` or `REMOVED`. Finishing the item folds the delta in.

#### Scenario: a delta that no longer fits the spec

- **Given** a delta with `MODIFIED Requirement: X` and a spec with no X
- **When** the delta is checked
- **Then** it says so, naming the capability and the requirement

#### Scenario: folding a delta that is partly stale

- **Given** a delta whose first entry cannot be applied and whose second can
- **When** it is folded
- **Then** the second is applied, the first is reported, and the item still
  completes

### Requirement: Every item tracks what is done and what is missing

Every item SHALL track what is done and what is missing.

An item carries a `## Steps` checklist. `- [x]` is a step that is done and
`- [ ]` is one that is not, and the count is read from the markdown rather than
stored beside it.

#### Scenario: an item part way through

- **Given** an item with two ticked steps and two unticked
- **When** it is shown, listed, or drawn on the board
- **Then** it reads `2/4`, and the board draws a bar half filled

#### Scenario: finishing with steps left unticked

- **Given** an item with two unticked steps
- **When** it is completed
- **Then** both are printed by name before the move

### Requirement: A project is set up for its assistants by one command

A project SHALL be set up for its assistants by one command.

`abydos-backlog init` makes the folders, writes the workflow document, and
writes the instruction file each chosen assistant reads. It is safe to run
again: files that belong to the project are left as they are, and a file the
project already had keeps everything outside our fenced section.

#### Scenario: running init twice

- **Given** a project set up for Claude Code, whose README has been edited
- **When** init is run again for opencode
- **Then** both assistants are configured, the edited README is untouched, and
  the workflow document is brought up to date

#### Scenario: instruction files the repository ignores

- **Given** a project whose `.gitignore` covers where an assistant's file goes
- **When** init writes it
- **Then** it says which files nobody who clones will get
