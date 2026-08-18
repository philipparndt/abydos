# Backlog

Everything left to do on a project lives in `.abydos/backlog/`, as markdown in
state folders. The app shows it in the bottom panel as a list and as a board,
`abydos-backlog` works it from a terminal, and an agent reads and moves the same
files: there is no database and no server, so the three of them cannot disagree
about what an item is or where it stands.

## Requirement: The backlog has a button on the left rail

The strip down the left edge of the window carries a button that shows the
backlog, first in the group at the bottom where the panes that dock below the
editor live. It is the same thing ⇧⌘B and Agent ▸ Backlog do.

**One button, and behind it whichever records of the work the project keeps.**
A project with `.abydos/backlog` shows that; one with `openspec/changes` shows
those; one with both offers a switch between them, and only then — a switch to
something that is not there does nothing twice. Two buttons on the rail both
meaning "what is left to do" is the confusion this avoids.

The switch is independent of list-or-board: which record is being looked at and
how it is drawn are different questions, and neither answers the other. Neither
is remembered between launches — a pane that opens on whatever was last looked
at opens differently for two people looking at the same project — and where
there is a backlog it opens on that, because that is the record somebody picks
work up from.

### Scenario: a window on a project

- **Given** a window with no backlog pane open
- **When** the checklist button at the bottom of the left rail is pressed
- **Then** the panel opens showing the backlog, board or list, whichever was
  last chosen

### Scenario: a project that keeps both

- **Given** a project with `.abydos/backlog` and `openspec/changes`
- **When** the pane is shown
- **Then** a control offers both, and choosing one redraws the same list or
  board for it

### Scenario: a project that keeps one

- **Given** a project with a backlog and no `openspec/` directory
- **When** the pane is shown
- **Then** there is no switch, and the pane is exactly what it was

## Requirement: A change's state is derived, and therefore not draggable

An OpenSpec change is a directory of markdown under `openspec/changes/<name>/`:
`proposal.md`, `design.md`, `specs/<capability>/spec.md` and `tasks.md`, with a
two-key `.openspec.yaml` beside them. **It has a name and no number, and nothing
in it records a state** — so where an item's state is the folder it sits in, a
change's is worked out from what is on the disk:

| column | when |
| --- | --- |
| Open | no `tasks.md` yet — still being written |
| Ready | `tasks.md` with nothing ticked |
| In progress | some ticked, some not |
| Completed | every task ticked |

Waiting is never answered for a change. Nothing in one says it is stuck on
something, and a marker invented here would be a format this project made up and
then had to keep.

Its fraction is the `- [x]` against the `- [ ]` in `tasks.md`, counted by the
same function that counts an item's `## Steps` — one parser, so a fraction means
the same thing on either card. A change with no `tasks.md` has no fraction at
all rather than `0/4`, and its card says which documents are written instead.

**A card for a change does not drag, and says why rather than merely not
moving.** An item drags between columns because moving its file *is* the change
of state; a change's column is read out of its files, so a drag could only mean
ticking or unticking checkboxes in a file nobody opened.

Archived changes — those under `changes/archive/` — are not a column. That is
`history`'s argument exactly: a long column beside four short ones is a wall
with the work hidden behind it, so they are in the list instead.

### Scenario: a change part-way through

- **Given** a change whose `tasks.md` has 4 of 30 ticked
- **When** the board is shown
- **Then** its card is in In progress and says 4/30

### Scenario: a box ticked somewhere else

- **Given** that board on screen
- **When** a task is ticked in a worktree or a terminal
- **Then** the card moves without the pane being clicked

### Scenario: dragging a change

- **Given** a change's card in Ready
- **When** it is dragged towards In progress
- **Then** it does not move, and the pane says a change's state comes from its
  tasks

## Requirement: A change is read from its files, not from a command

The board reads `openspec/changes/` directly and **never runs the `openspec`
CLI**. Measured on this machine, `openspec list --json` costs 0.60 s and
`openspec status --change` another 0.60 s each — Node start-up, not work — and
the pane re-reads whenever anything under the directory changes, including an
agent ticking a box. A change is committed markdown, so a teammate with no Node
still has all of it.

Where the tool *is* wanted — archiving, which moves a change and folds its specs
into the project's — it is found through the same search that finds any tool a
version manager owns, and its absence is a sentence rather than a menu entry
that does nothing. On the machine this was written on it lives at
`~/.local/state/fnm_multishells/91100_…/bin/openspec`, an fnm directory with a
shell's PID in its name, and a Dock-launched app's `PATH` is four system
directories.

Archiving is handed over rather than run: it rewrites the project's specs, which
is the larger half of somebody's review.

### Scenario: no CLI on the machine

- **Given** a project with `openspec/changes/` and no `openspec` anywhere
- **When** the pane is shown
- **Then** every change is there, with its progress

### Scenario: a finished change

- **Given** a change with every task ticked
- **When** its menu is opened
- **Then** it offers the `openspec archive <name>` command to copy, or says the
  tool is not installed

## Requirement: A card offers the worktree its item is being worked on in

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

## Requirement: A project with no backlog is offered one

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

## Requirement: An item filed from the pane lands in open

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

## Requirement: A card's progress is the worktree's, and says so

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

### Scenario: an agent has ticked three of six on its branch

- **Given** an item in `in-progress/` whose worktree's copy has three of six
  steps ticked, and whose copy in the project has none
- **Then** its card reads `3/6 in the worktree`, and the item stays in the
  in-progress column

### Scenario: the branch has parked the item and the project has not

- **Given** an item whose worktree's copy has been moved to `waiting/` on the
  branch, while the project's copy is still in `in-progress/`
- **Then** the card is still in the in-progress column, and still shows the
  branch's fraction — the copy is found by number, not by where it sits

### Scenario: a worktree somebody deleted

- **Given** a card for an item whose recorded worktree has been removed
- **Then** the fraction is the project's copy and the card says `0/6 in the
  project`

## Requirement: An item says how much longer it has

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

## Requirement: `abydos-backlog` works wherever it is run from

The command ships in three places — inside the app at
`Abydos.app/Contents/Resources/bin/`, on the `PATH` after `make install-cli`,
and beside the binaries of a checkout — and every subcommand behaves the same in
all three. In particular it never fails for want of a resource it ships with:
where the app's resource bundles can be found, they are used; where they cannot,
whatever needed them falls back, and nothing aborts.

### Scenario: the copy inside the app picks an item up

- **Given** `Abydos.app/Contents/Resources/bin/abydos-backlog`, whose own
  directory holds no resource bundles
- **When** `start <number>` is run on a ready item
- **Then** the worktree is made, the item moves to `in-progress/`, and the
  configured assistant is started in the worktree

### Scenario: a copy with no resource bundles anywhere near it

- **Given** the command installed by `make install-cli`, in `/usr/local/bin`
- **When** `start <number>` is run
- **Then** it does the same thing, reading its settings without the shipped
  colour schemes rather than failing

## Requirement: A start that cannot launch an agent says where the work is

Half of `start` cannot be undone: by the time an agent could fail to launch, the
branch exists, the worktree exists, and the item has moved to `in-progress/` in
both checkouts. So the worktree and the branch are printed as soon as they
exist, before anything is asked of the assistant, and an agent that does not
start is followed by the directory to `cd` into and the prompt it would have
been given. An item that looks picked up and is not is the one outcome this
must not have.

### Scenario: no assistant is installed

- **Given** a backlog configured for an assistant that is not on this machine
- **When** `start <number>` is run
- **Then** it prints the branch and the worktree, says nothing was started, and
  prints the directory and the prompt to hand to an agent by hand

### Scenario: the assistant cannot be run

- **Given** a configured assistant whose binary refuses to start
- **When** `start <number>` is run
- **Then** the failure is reported, and the worktree and prompt are printed so
  the item can be picked up by hand

## Requirement: An item's state is the folder it is in

Nothing records a state anywhere else. An item is in `open/`, `ready/`,
`in-progress/`, `waiting/`, `completed/` or `history/`, and moving it along
moves the file or the folder, keeping the number it was given.

### Scenario: moving an item that carries screenshots

- **Given** `open/0443-something/` with `task.md` and two files in `images/`
- **When** it is moved to `ready`
- **Then** it is `ready/0443-something/` with both files still in it
- **And** it still answers to the number 443

### Scenario: a number is given once

- **Given** a backlog whose highest number anywhere, `history/` included, is 442
- **When** a new item is written
- **Then** it is 443, and no existing item's number changes

## Requirement: An item is a file, or a folder when it carries something

An entry in a state folder is an item if it is a `.md` file, or a directory
containing `task.md`. Both are read the same way: the same title, the same
number, the same checklist.

### Scenario: attaching a file to an item that is one file

- **Given** `open/0443-something.md`
- **When** a screenshot is attached to 443
- **Then** it becomes `open/0443-something/task.md` with the screenshot in
  `images/`, and the markdown is unchanged

### Scenario: two screenshots of the same name

- **Given** an item that already carries `Screenshot.png`
- **When** another file called `Screenshot.png` is attached
- **Then** both are kept, the second as `Screenshot-2.png`

## Requirement: An agent the backlog starts can find the house rules

`start` launches an agent, and until it did every agent was handed its item by a
person who also told it how to behave on this machine. The prompt it builds does
not carry those rules and SHALL NOT: it names `AGENTS.md`, `project.md` and the
item, and its own comment gives the reason — a second copy drifts, and the drift
is invisible because nobody reads the prompt a button builds.

The rules SHALL exist in exactly one place, reachable both by an agent the tool
started and by one nobody started. `CLAUDE.md` at the repository root is that
place: it is read without being pointed at, which covers most agents, and
`project.md` names it for the rest. Nothing else states a rule — a document that
mentions one may point at the file, never repeat it.

**Each rule SHALL carry the failure that motivated it.** "Never push" is obeyed;
"never push, because an agent once created five public Docker Hub repositories
nobody asked for" is understood, and an understood rule generalises to the case
the list does not mention.

**What is true today lives elsewhere.** `.abydos/today.md` holds which sessions
are somebody's, what is running and what is known to be noisy — separate so that
the rules can be trusted, since a document mixing "never push" with a fact about
a Tuesday teaches an agent to distrust all of it, and so that correcting it is
not a commit that reads like a policy change.

A rule a program already keeps SHALL say so, because that is a rule an agent can
stop worrying about and the rest are where the attention belongs.

### Scenario: an item picked up by the tool

- **GIVEN** an item started with `abydos-backlog start`
- **WHEN** the agent reads what the prompt names
- **THEN** `project.md` points it at `CLAUDE.md`
- **AND** the prompt itself states none of the rules

### Scenario: an agent nobody started through the backlog

- **GIVEN** an assistant opened on this repository directly
- **WHEN** it reads what it reads by default
- **THEN** `CLAUDE.md` is the house rules, in full

### Scenario: no agent to launch

- **GIVEN** a project with no assistant configured
- **WHEN** an item is started
- **THEN** the worktree is made, the item is moved, and the `cd` and the prompt
  are printed for a person to hand over — which is now a path somebody may take
  deliberately rather than a workaround for rules the prompt was missing

## Requirement: Ready is the only folder an agent picks from

`ready` means the deciding is done. Nothing moves an item into it
automatically, and picking one up is refused for an item in any other state.

### Scenario: asking for the next thing to do

- **Given** items in `open/` and two in `ready/`, numbered 12 and 8
- **When** the next item is asked for
- **Then** it is 8, and nothing in `open/` is offered

## Requirement: An item is picked up into a worktree of its own

Starting an item makes a git worktree on `backlog/<number>-<slug>`, moves the
item to `in-progress/` in both the project and the worktree, records the run on
this machine, and starts the configured assistant there.

### Scenario: an item that is not committed

- **Given** a ready item that has never been committed
- **When** it is started
- **Then** it is refused, and stays in `ready/`, because a worktree is a
  checkout of HEAD and would not contain the item

### Scenario: an item already being worked on

- **Given** an item whose worktree exists
- **When** it is started again
- **Then** it is refused and names the worktree

## Requirement: The spec says what the project does, and items change it by delta

`spec/` holds one file per capability. An item that changes behaviour carries
`spec/<capability>.md` in its own folder, with each requirement headed `ADDED`,
`MODIFIED` or `REMOVED`. Finishing the item folds the delta in.

### Scenario: a delta that no longer fits the spec

- **Given** a delta with `MODIFIED Requirement: X` and a spec with no X
- **When** the delta is checked
- **Then** it says so, naming the capability and the requirement

### Scenario: folding a delta that is partly stale

- **Given** a delta whose first entry cannot be applied and whose second can
- **When** it is folded
- **Then** the second is applied, the first is reported, and the item still
  completes

## Requirement: Every item tracks what is done and what is missing

An item carries a `## Steps` checklist. `- [x]` is a step that is done and
`- [ ]` is one that is not, and the count is read from the markdown rather than
stored beside it.

### Scenario: an item part way through

- **Given** an item with two ticked steps and two unticked
- **When** it is shown, listed, or drawn on the board
- **Then** it reads `2/4`, and the board draws a bar half filled

### Scenario: finishing with steps left unticked

- **Given** an item with two unticked steps
- **When** it is completed
- **Then** both are printed by name before the move

## Requirement: A project is set up for its assistants by one command

`abydos-backlog init` makes the folders, writes the workflow document, and
writes the instruction file each chosen assistant reads. It is safe to run
again: files that belong to the project are left as they are, and a file the
project already had keeps everything outside our fenced section.

### Scenario: running init twice

- **Given** a project set up for Claude Code, whose README has been edited
- **When** init is run again for opencode
- **Then** both assistants are configured, the edited README is untouched, and
  the workflow document is brought up to date

### Scenario: instruction files the repository ignores

- **Given** a project whose `.gitignore` covers where an assistant's file goes
- **When** init writes it
- **Then** it says which files nobody who clones will get
