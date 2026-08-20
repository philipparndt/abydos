# openspec-board Specification

## Purpose
TBD - created by archiving change backlog-view-shows-openspec-changes. Update Purpose after archive.
## Requirements
### Requirement: The pane shows whichever records of work a project keeps

The backlog pane SHALL show OpenSpec changes for a project with an `openspec/`
directory, and the backlog for a project with `.abydos/backlog`, and SHALL offer a
switch between them only where the project has both. Two rail buttons that both
mean "what is left to do" are not the answer; one pane with a source is.

The switch SHALL be independent of the list/board toggle: which record is being
looked at and how it is drawn are different questions.

A project with neither SHALL be offered both, rather than only the one this pane
had first.

#### Scenario: a project with both

- **GIVEN** this repository, which has `.abydos/backlog` and `openspec/changes`
- **WHEN** the pane is shown
- **THEN** a control offers both, and choosing one redraws the same list or board
  for it

#### Scenario: a project with only one

- **GIVEN** a project with a backlog and no `openspec/` directory
- **WHEN** the pane is shown
- **THEN** no source switch appears, and the pane is exactly what it is today

#### Scenario: a project with neither

- **GIVEN** a project with neither
- **WHEN** the pane is shown
- **THEN** both are offered — making a backlog, and setting up OpenSpec — with
  the command each one is named beside it

### Requirement: A change lands in a column that says where it stands

Each change SHALL be placed in a board column from its derived state, and **the
columns SHALL be OpenSpec's own rather than the backlog's folders**. Measured
against the installed CLI, OpenSpec answers in three vocabularies at three
levels: a change is `no-tasks`, `in-progress` or `complete`; each artifact is
`done`, `ready` or `blocked`; and applying is `blocked`, `ready` or `all_done`.
The board takes the last, because "can this be picked up" is the question a board
answers and is what `ready` means on the backlog's board too:

| column | when |
| --- | --- |
| Writing | an artifact `apply` requires is missing |
| Ready | every required artifact is there and no task is ticked |
| In progress | some tasks ticked, some not |
| Complete | every task ticked, and not yet archived |
| Archived | under `changes/archive/` |

Waiting SHALL never be answered for a change. Nothing in one says it is stuck on
something, and a marker invented here would be a format this project made up and
then had to keep.

**Ready and In progress are one state to `openspec list`**, which calls both
`in-progress` because it only counts tasks. The board SHALL separate them: "nobody
has started" against "somebody is in the middle of this" is most of what a board
is for, and nothing reports a different answer to anything but the eye — the
fraction on the card is the number the CLI gives either way.

**`isComplete` from the CLI SHALL NOT be read as finished.** It means every
artifact needed to *start* exists, so a change with a full set of documents and
nothing ticked has it.

**Archived changes SHALL be a column, and it SHALL be the last one.** This said
the opposite, on the argument that keeps the backlog's `history` off its board —
and that argument is the reverse of this case. The backlog excludes `history`
because it is 390 records from before the backlog existed *while `completed/` is
on the board beside it*; OpenSpec has no `completed/` at all, so a change moves to
`changes/archive/` the moment it is done. Excluding it left a project that had
just archived nine changes showing five empty columns.

#### Scenario: a change part-way through

- **GIVEN** a change whose `tasks.md` has 4 of 30 ticked
- **WHEN** the board is shown
- **THEN** its card is in In progress and says 4/30

#### Scenario: a change nobody has started

- **GIVEN** a change with every required artifact and nothing ticked
- **WHEN** the board is shown
- **THEN** its card is in Ready, not in In progress

#### Scenario: a change still being written

- **GIVEN** a change with a proposal and no tasks
- **WHEN** the board is shown
- **THEN** its card is in Writing and says what it needs next

#### Scenario: an agent ticks a box

- **GIVEN** that board on screen
- **WHEN** a task in one change is ticked in a worktree or a terminal
- **THEN** the card moves without the pane being clicked

#### Scenario: a project whose changes are all archived

- **GIVEN** a project with nine archived changes and no active ones
- **WHEN** the board is shown
- **THEN** the nine are in the Archived column rather than the board being empty

### Requirement: A change cannot be dragged between columns

Dragging SHALL be refused for a change's card, and the refusal SHALL say why
rather than the card simply not moving. A backlog item drags because moving its
file is what changing its state means; a change's column is read out of its files,
so a drag could only mean rewriting checkboxes nobody opened.

#### Scenario: dragging a change

- **GIVEN** a change's card in Ready
- **WHEN** it is dragged towards In progress
- **THEN** it does not move, and the pane says a change's state comes from its
  tasks

#### Scenario: backlog cards still drag

- **GIVEN** the same pane switched to the backlog
- **WHEN** an item is dragged from Ready to In progress
- **THEN** it moves, exactly as it does today

### Requirement: A card opens the change it stands for

A change's card SHALL open its artifacts in the editor — `proposal.md`,
`design.md`, `tasks.md` and each `specs/<capability>/spec.md` — since reading and
editing them is what a change is for.

Before any task is ticked, the card SHALL say which artifacts exist, because at
that stage that is what "how far along is it" means.

#### Scenario: opening a change

- **GIVEN** a card for `completions-say-what-goes-in-them`
- **WHEN** it is opened
- **THEN** the change's artifacts are reachable in the editor from it

#### Scenario: a change with a proposal and nothing else

- **GIVEN** a change directory with `proposal.md` alone
- **WHEN** its card is drawn
- **THEN** it says the proposal is written and the rest is not, rather than
  showing an empty fraction

### Requirement: The `openspec` CLI is found the way a version manager's tools are

The CLI SHALL be located through the same search that finds a tool a version
manager owns, wherever it is wanted for something that writes — archiving,
validating — and its absence SHALL be said rather than being a verb that does
nothing. On this
machine `openspec` is at
`~/.local/state/fnm_multishells/91100_1786908065368/bin/openspec`, an fnm
directory with a shell's PID in its name, and an app launched from the Dock has
`PATH=/usr/bin:/bin:/usr/sbin:/sbin`.

#### Scenario: the CLI is behind a version manager

- **GIVEN** `openspec` installed only under an fnm multishell directory
- **WHEN** a verb that needs it is used
- **THEN** it is found, because the login shell is asked

#### Scenario: the CLI is not installed

- **GIVEN** a machine with no `openspec` at all
- **WHEN** a verb that needs it is used
- **THEN** the pane says so and says how to get it
- **AND** everything that only reads the directory still works

### Requirement: Each source brings its own columns

The board SHALL take its columns from whichever record is being shown. The
backlog's are its folders — open, ready, in-progress, waiting, completed — and
OpenSpec's are the lifecycle above. Neither is imposed on the other: one set of
columns for two records is what put a change into a folder it has no notion of.

#### Scenario: switching between the two

- **GIVEN** a project with both records
- **WHEN** the source is switched
- **THEN** the columns change to that record's own

### Requirement: A card offers the command that starts work on it

A change's card SHALL offer, to copy, the command that picks the change up:

    /opsx:apply changes-are-shown-in-openspecs-own-states

**Not `openspec apply`, because the CLI has no such verb.** Its commands are
`init`, `update`, `list`, `view`, `change`, `archive`, `spec`, `config`,
`schema`, `validate`, `show`, `status`, `instructions`, `feedback` and
`completion`; applying is `openspec instructions apply --change <name>` printing
what to do and an agent then doing it. The command a person pastes is the slash
command, which lives in `.claude/commands/opsx/apply.md` in the project itself.

**It SHALL be offered only where the change can be picked up** — a change in
Ready. A change still being written cannot be applied and OpenSpec says so
itself, answering `blocked` for apply while an artifact is missing; a Complete or
Archived change has nothing left to apply, and a Complete one already offers
`openspec archive <name>`. An entry that hands somebody a command which is then
refused is worse than no entry.

**A change part-way through SHALL offer three sentences instead**, because
picking a change up and carrying on with one are not the same thing to say, and
which of the three is right is a judgement only the person looking at the card
can make:

    archive <name> as it is
    complete <name>, I have verified it
    continue on <name>

The first is for work that is done enough, with what is left deliberately not
taken — a thing that happens, and better written into the record than left as a
change nobody closes. The second is for work that *is* done while the boxes are
not ticked, because what proves them is somebody watching the app rather than a
suite: **the person saying it is the evidence**, and the sentence says so out
loud rather than letting an assistant tick boxes on its own say-so. The third is
the ordinary one.

They are sentences rather than slash commands for the same reason: two of the
three are a person telling an assistant something it cannot find out for itself.

**Copied rather than run, and for a different reason than the archive
command's.** Archiving is not run from the menu because it rewrites the project's
specs. This is not run because there is nothing here to run it *with*: it is
typed into an assistant, not into a shell.

**It SHALL NOT depend on the CLI being installed.** The archive entry needs
`openspec` found and says so when it is missing; this one needs no executable at
all, so looking for one — and refusing on not finding it — would answer a
question that was never asked.

#### Scenario: a change waiting to be picked up

- **GIVEN** a card in Ready
- **WHEN** its menu is opened
- **THEN** the menu offers to copy `/opsx:apply <name>`
- **AND** copying it puts exactly that on the pasteboard

#### Scenario: a change part-way through

- **GIVEN** a card in In progress with 4 of 30 ticked
- **WHEN** its menu is opened
- **THEN** the three sentences are offered — archive it as it is, complete it as
  verified, carry on — and the apply command is not

#### Scenario: a change still being written

- **GIVEN** a card in Writing, whose `tasks.md` is missing
- **WHEN** its menu is opened
- **THEN** the apply command is not offered

#### Scenario: a finished change

- **GIVEN** a card in Complete
- **WHEN** its menu is opened
- **THEN** the archive command is offered and the apply command is not

#### Scenario: a machine without the CLI

- **GIVEN** a project on a machine with no `openspec` installed
- **WHEN** a Ready card's menu is opened
- **THEN** the apply command is still offered

