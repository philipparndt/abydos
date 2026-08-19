## MODIFIED Requirements

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
