# Trashing Files

## Purpose

What ⌘⌫ and *Move to Trash* do in the project tree: what the tree shows while
the trash is at work, what happens when the trash refuses, what a second
press does, and what undo puts back.

## ADDED Requirements

### Requirement: A trashed row goes at once

The tree SHALL take a row out of the tree the moment ⌘⌫ or *Move to Trash*
is pressed on it, before the trash has answered, and SHALL put the selection
on the surviving row as `tree-behaviour` says. The file SHALL be moved to the
trash rather than deleted, without a confirmation.

#### Scenario: ⌘⌫ on a file

- **GIVEN** `src/main.py` selected
- **WHEN** ⌘⌫ is pressed
- **THEN** the row is gone from the tree in the same event, and the selection is on the row that survived above it

#### Scenario: a collapsed folder

- **GIVEN** a folder row that has never been expanded, selected
- **WHEN** ⌘⌫ is pressed
- **THEN** its row is gone at once and stays gone after the trash has answered

### Requirement: A refusal brings the row back

When the trash refuses a file, the tree SHALL put its row back beside the
toast that says why, and SHALL keep gone what the trash did move.

#### Scenario: one of three refused

- **GIVEN** three rows selected, one of them a file the trash cannot take
- **WHEN** ⌘⌫ is pressed
- **THEN** two rows are gone, the third is back, and a toast says why

### Requirement: A second press on a stale row refreshes rather than errors

⌘⌫ on a row whose file is no longer on disk SHALL NOT be sent to the trash
and SHALL NOT produce an error; the tree SHALL re-read the row's folder
instead.

#### Scenario: the file was deleted in a terminal

- **GIVEN** a row whose file `rm` removed a moment ago
- **WHEN** ⌘⌫ is pressed
- **THEN** no toast appears and the row is gone

### Requirement: Undo puts the file back from the trash's own answer

⌘Z in the tree after a trash SHALL move each file back from where the trash
put it to where it was, and its row SHALL reappear selected. The undo SHALL
be recorded from the trash's answer, so a file the trash renamed on
collision comes back under its own name.

#### Scenario: trash then undo

- **GIVEN** `src/main.py` just trashed
- **WHEN** ⌘Z is pressed with the tree holding the keyboard
- **THEN** `src/main.py` is back on disk and its row is selected

### Requirement: A driven run shows the row gone before the trash answers

A driven run SHALL be able to show that the row is gone with no settle at
all, that the file is gone after one, and that undo brings both back.

#### Scenario: the harness's settle is the number under test

- **GIVEN** a scratch project in a driven run with `src/main.py` selected
- **WHEN** the steps `cmd-delete,rows,settle,ls:src,undo-key,settle,rows,ls:src` run
- **THEN** the first `rows` lacks `main.py`, the first `ls` lacks it, and the second of each has it back
