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
- **THEN** the existing offer to make a backlog is what is shown

### Requirement: A change lands in a column that says where it stands

Each change SHALL be placed in a board column from its derived state: still being
written in Open, ready to pick up in Ready, part-done in In progress, all tasks
ticked in Completed. The Waiting column SHALL stay empty for changes.

Archived changes SHALL NOT be a column. `changes/archive/` is the same argument
`history` is excluded by — a long column beside four short ones is a wall with the
work hidden behind it — and they SHALL be reachable from the list instead.

#### Scenario: the eight changes in this repository

- **GIVEN** eight changes, each with a `tasks.md` and nothing ticked
- **WHEN** the board is shown for OpenSpec
- **THEN** all eight are in Ready, and Open, In progress and Completed are empty

#### Scenario: an agent ticks a box

- **GIVEN** that board on screen
- **WHEN** a task in one change is ticked in a worktree or a terminal
- **THEN** the card moves to In progress without the pane being clicked

#### Scenario: the archive

- **GIVEN** changes under `changes/archive/`
- **WHEN** the board is shown
- **THEN** none of them is on it
- **AND** they are findable in the list

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

