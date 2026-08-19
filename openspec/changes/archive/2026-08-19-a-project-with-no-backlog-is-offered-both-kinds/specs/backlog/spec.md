## MODIFIED Requirements

### Requirement: A project with no backlog is offered one

A project with no record of work SHALL be offered both kinds this pane can read:
a backlog and an OpenSpec directory.

Where there is neither `.abydos/backlog` nor `openspec/`, the pane says so
rather than drawing an empty board, and offers both. **Making a backlog** is the
same code `abydos-backlog init` runs, for the assistants installed on this
machine; once it is made the pane shows the board without being reopened, and
opens the workflow document, which is what `init` on the command line says to
read next. **Setting up OpenSpec** opens a terminal in the project and runs
`openspec init` there, because that command asks which assistants to write slash
commands and skills for, and those answers belong to whoever owns the
repository. Each offer SHALL name the command it is, so that it can be typed
instead.

Where the `openspec` CLI is not installed, the OpenSpec offer SHALL say so and
how to get it, rather than being a button that runs nothing.

The offer SHALL be drawn as the editor draws a file it cannot show: an icon, a
title, one line of reason, and a row of buttons under it. The button they share
SHALL have one implementation, so that the two cannot come to look different.

#### Scenario: opening the pane in a project with neither

- **GIVEN** a project with no `.abydos/backlog` and no `openspec/`
- **WHEN** the backlog is shown
- **THEN** it says the project has no record of work and offers both, naming
  `abydos-backlog init` and `openspec init` as the same things from a terminal

#### Scenario: making a backlog

- **GIVEN** that offer, agreed to
- **THEN** the state folders, the workflow, `project.md`, the spec and the
  instruction files are written, and the pane shows the board over them

#### Scenario: setting up OpenSpec

- **GIVEN** the same offer, and `openspec` installed
- **WHEN** the OpenSpec button is used
- **THEN** a terminal opens in the project running `openspec init`, with its
  questions left to be answered there
- **AND** the pane shows the board once an `openspec/` exists, without being
  reopened

#### Scenario: OpenSpec is not installed

- **GIVEN** a machine with no `openspec` on it
- **WHEN** the pane is shown for a project with neither record
- **THEN** the OpenSpec offer says it is not installed and how to get it, and
  cannot be pressed
- **AND** the backlog offer is unaffected
