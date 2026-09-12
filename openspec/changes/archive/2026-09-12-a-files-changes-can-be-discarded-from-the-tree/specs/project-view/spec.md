# Project View

## ADDED Requirements

### Requirement: A changed file's changes can be discarded from the tree

The tree's context menu SHALL offer *Discard Changes*, worded by the same rule
the Changes pane uses, over any selection of rows that git could discard — a
file whose status is not unmodified or ignored, a folder holding such files —
and SHALL hide it otherwise, over a conflicted row included. Choosing it SHALL
ask the same question the Changes pane asks, naming the folder and counting
untracked files, SHALL make the safety-net ref before restoring anything, and
SHALL discard through the one operation the pane uses, with the same toast.
The verb SHALL be reachable without the Changes pane being open. Afterwards an
editor tab on the file SHALL reload from disk and the tree's colour SHALL
follow.

Reported 2026-09-10: the menu offered every way of looking at a changed file
and no way to put it back.

#### Scenario: a modified file

- **GIVEN** a file the tree colours as modified
- **WHEN** it is right-clicked
- **THEN** the menu offers *Discard Changes*, and choosing it and confirming
  leaves the file as the last commit had it, with the tree's colour gone

#### Scenario: a folder with changes under it

- **GIVEN** a folder holding two modified files and one untracked one
- **WHEN** it is right-clicked
- **THEN** the item's title counts them the way the Changes pane would, and the
  question names the folder

#### Scenario: an unchanged file

- **GIVEN** a file the tree colours as unmodified
- **WHEN** it is right-clicked
- **THEN** the item is absent

#### Scenario: a conflict

- **GIVEN** a conflicted file
- **WHEN** it is right-clicked
- **THEN** the item is absent, as the Changes pane refuses one

#### Scenario: an open tab

- **GIVEN** the modified file open in the editor
- **WHEN** its changes are discarded from the tree
- **THEN** the tab shows the file as the last commit had it

#### Scenario: a driven run

- **GIVEN** a driven run on a scratch checkout with a modified file selected
- **WHEN** its `discard` step runs
- **THEN** it prints the item's title and the question, and discards nothing;
  `discard-confirm` discards and prints the file's status as clean
