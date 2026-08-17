## ADDED Requirements

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
OpenSpec change records a state the way a backlog item's folder does:

- no `tasks.md` — still being written
- `tasks.md` with nothing ticked — ready to be picked up
- some tasks ticked — in progress
- every task ticked — done
- inside `changes/archive/` — archived

No change SHALL be reported as waiting: nothing on disk says a change is stuck,
and a marker invented here would be a format this project made up.

#### Scenario: every task ticked

- **GIVEN** a change whose `tasks.md` has no `- [ ]` left
- **WHEN** it is read
- **THEN** its state is done

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
