## MODIFIED Requirements

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

## ADDED Requirements

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
Ready or In progress. A change still being written cannot be applied and OpenSpec
says so itself, answering `blocked` for apply while an artifact is missing; a
Complete or Archived change has nothing left to apply, and a Complete one already
offers `openspec archive <name>`. An entry that hands somebody a command which is
then refused is worse than no entry.

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
- **THEN** the same command is offered, since the rest is still to do

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
