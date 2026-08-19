# openspec-reading Specification

## Purpose
TBD - created by archiving change backlog-view-shows-openspec-changes. Update Purpose after archive.
## Requirements
### Requirement: A change is read from its directory, not from a command

The editor SHALL read an OpenSpec change from the files in
`openspec/changes/<name>/` and SHALL NOT require the `openspec` CLI to be
installed in order to show one. A change is committed markdown: a project whose
collaborator has no Node on the machine still has all of it.

Measured on this machine, `openspec list --json` costs 0.60 s and `openspec status
--change <name> --json` another 0.60 s each — Node start-up — and the pane reloads
on every file-system event under the directory it watches.

#### Scenario: no CLI installed

- **GIVEN** a project with `openspec/changes/` and no `openspec` on any path
- **WHEN** the pane is shown
- **THEN** every change in that directory is listed, with its progress

#### Scenario: nothing is spawned to draw

- **GIVEN** a project with eight changes
- **WHEN** the pane reloads
- **THEN** no process is started to work out what to draw

### Requirement: A change's progress is its ticked tasks

Progress SHALL be the count of `- [x]` against the count of all `- [ ]` and
`- [x]` lines in the change's `tasks.md`, and SHALL be produced by the same
counting that gives a backlog item its fraction under `## Steps`. One parser, so
that a fraction means the same thing on either kind of card.

A change with no `tasks.md` SHALL have no fraction rather than `0/0`.

#### Scenario: a change part-way through

- **GIVEN** a `tasks.md` with 30 checkboxes, 4 of them `- [x]`
- **WHEN** the change is read
- **THEN** its progress is 4 of 30

#### Scenario: a change with no tasks yet

- **GIVEN** a change directory holding only `proposal.md` and `.openspec.yaml`
- **WHEN** it is read
- **THEN** it has no progress at all, and asking for one does not divide by zero

### Requirement: A change's state is derived from what is on disk

The state SHALL be worked out from the change's own files, since nothing in an
OpenSpec change records a state the way a backlog item's folder does — and it
SHALL be named in OpenSpec's own vocabulary rather than the backlog's:

- an artifact `apply` requires is missing — **writing**
- every required artifact present and nothing ticked — **ready**
- some tasks ticked — **in progress**
- every task ticked — **complete**
- inside `changes/archive/` — **archived**

`spec-driven`'s `apply.requires` is `[tasks]`, and `tasks` requires `specs` and
`design`, which require `proposal` — so `tasks.md` on the disk implies the whole
chain, which is what makes every state above readable from a directory listing
rather than from the CLI.

No change SHALL be reported as waiting: nothing on disk says a change is stuck,
and a marker invented here would be a format this project made up.

**Ready and in progress are one state to `openspec list`**, which calls both
`in-progress` because it counts tasks and nothing else. They SHALL be kept apart
here, and the reason SHALL be stated where it is done: the CLI is answering "has
work started" and a board is answering "what can I pick up". The fraction is the
number the CLI reports either way, so nothing disagrees but the naming.

#### Scenario: every task ticked

- **GIVEN** a change whose `tasks.md` has no `- [ ]` left
- **WHEN** it is read
- **THEN** its state is complete

#### Scenario: nothing ticked

- **GIVEN** a change with every required artifact and no `- [x]`
- **WHEN** it is read
- **THEN** its state is ready, not in progress

#### Scenario: an archived change

- **GIVEN** a directory under `openspec/changes/archive/`
- **WHEN** the changes are read
- **THEN** it is reported as archived, whatever its tasks say

### Requirement: The change header is read without a YAML dependency

`.openspec.yaml` carries two keys — `schema` and `created`. The editor SHALL read
them as lines and SHALL NOT add a YAML parser to the project for them. A header
that grows something structural is a reason to revisit this, written down at the
time.

#### Scenario: the header this tool writes

- **GIVEN** `.openspec.yaml` containing `schema: spec-driven` and
  `created: 2026-08-17`
- **WHEN** the change is read
- **THEN** both values are available

#### Scenario: a missing or unreadable header

- **GIVEN** a change directory with no `.openspec.yaml`
- **WHEN** it is read
- **THEN** it is still a change, with its artifacts and its tasks, and no error

### Requirement: A change whose schema this reader does not know is named, not guessed

A change whose schema this reader does not know SHALL be named as such rather
than sorted by rules that do not apply to it. Every state on the board is worked
out from which files exist, and that is only sound for the schema those rules
were written from. `spec-driven` requires
`tasks` to apply, and its `tasks` requires `specs` and `design`, which require
`proposal` — so "`tasks.md` exists" implies the whole chain, and the lifecycle
follows from the files alone. That is what makes reading the directory
affordable, and it is true for exactly one schema.

A change carries the schema it was made with in `.openspec.yaml`. Where that is
anything else, the reader SHALL say so on the card and SHALL NOT sort it by rules
that do not apply to it. A card that says its schema is unknown is one somebody
can act on; a card placed by the wrong rule is not.

Where the header is missing entirely, the change is read as `spec-driven` — that
is what `openspec new change` writes, and a change with no header is far more
likely to be one somebody hand-made than one using a schema they did not record.

#### Scenario: a change made with another schema

- **GIVEN** a change whose `.openspec.yaml` names a schema other than
  `spec-driven`
- **WHEN** the board is shown
- **THEN** its card says the schema is one this reader does not know
- **AND** it is not placed in Ready, In progress or Complete

#### Scenario: a change with no header at all

- **GIVEN** a change directory with no `.openspec.yaml`
- **WHEN** it is read
- **THEN** it is read as `spec-driven`, as before

### Requirement: What a change is waiting for is on its card

A card SHALL say what is written and what is needed next while a change is still
being written. OpenSpec answers that per artifact — `done`, `ready`, `blocked` —
and which document is missing is the useful thing at that stage. A silent card in
a column is the state this replaces.

#### Scenario: a change with a proposal and nothing else

- **WHEN** its card is drawn
- **THEN** it says the proposal is written and names what comes next

#### Scenario: a change with everything but tasks

- **WHEN** its card is drawn
- **THEN** it says tasks are what it needs

