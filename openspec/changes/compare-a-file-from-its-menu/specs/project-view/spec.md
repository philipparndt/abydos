# Project view — delta

## ADDED Requirements

### Requirement: A file row offers the two ways of comparing the file

A file row's context menu SHALL carry a Compare submenu: **Against Last
Commit**, opening the file's diff against HEAD — staged and unstaged edits in
one answer — and **History…**, opening the log page scoped to that file, the
same page the log's "This File" segment reaches. The submenu tells the truth
per row: an untracked file offers Against Last Commit disabled and no
History… (git holds neither a last commit of it nor a history), and rows
that are not files in the repository — folders, dependencies, session roots —
carry no Compare at all.

Both destinations existed and neither was reachable from the file it is
about: the diff meant finding the file again in the changes tree, the file's
history meant opening a log on something else first.

#### Scenario: a changed file compared against the last commit

- **GIVEN** a tracked file with a staged and an unstaged edit
- **WHEN** Compare ▸ Against Last Commit is chosen on its row
- **THEN** a diff tab opens showing both edits against HEAD

#### Scenario: a file's history from its row

- **WHEN** Compare ▸ History… is chosen on a tracked file's row
- **THEN** the log page opens scoped to that file, its scope control showing
  "This File", following the file across renames as that page does

#### Scenario: an untracked file has no history to offer

- **GIVEN** a file never committed
- **THEN** its Compare submenu shows Against Last Commit disabled and no
  History…
