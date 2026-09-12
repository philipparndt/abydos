# Project View

## ADDED Requirements

### Requirement: The tree says when it is reading, and can be asked to

The project tree SHALL show the same hairline sweep under its header while a
project is being loaded and while a reload's status sweep and dependency walk
run, and SHALL NOT show it for the watcher's per-event status reads. The
tree's header SHALL offer a refresh button, after its three existing buttons,
that re-reads the folder and the working copy's status.

Asked for 2026-09-12: the waiting strip as a general feature of every pane,
and a refresh on the project pane.

#### Scenario: Opening a large repository

- **GIVEN** a repository whose status sweep takes a moment
- **WHEN** it is opened
- **THEN** the sweep runs under the tree's header until the tree is coloured, and stops

#### Scenario: Pressing refresh

- **GIVEN** a build has written files the watcher has not yet reported
- **WHEN** the header's refresh button is pressed
- **THEN** the tree is re-read from disk and recoloured, with the sweep under the header until both have answered

#### Scenario: A file saved

- **GIVEN** the tree showing
- **WHEN** a file is written and the watcher re-reads the status
- **THEN** no sweep is shown
