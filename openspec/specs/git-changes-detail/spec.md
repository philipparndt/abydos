# Git changes detail

## Purpose

What a row in a list of changes says about itself — whether it holds other rows, what is inside it when it does, and how much of it changed — and the cost of asking, which is what decided the shape: a wholly untracked directory arrives from git as one entry and is opened one directory at a time.

## Requirements

### Requirement: An untracked directory reads as a directory

A row standing for a wholly untracked directory SHALL be drawn as a directory —
its own icon and a disclosure triangle — and SHALL NOT be drawn as a file.

Git reports such a directory as one record on purpose: the listing asks for
`-unormal` because `-uall` took seven seconds on a work tree of 69,829 untracked
files and the listing runs on every filesystem event. One record is the right
thing to receive. A file is the wrong thing to draw.

#### Scenario: an untracked folder in the working copy

- **GIVEN** a directory `PI-12` that git is not tracking, holding files
- **WHEN** the working copy's changes are listed
- **THEN** its row carries a folder icon and a disclosure triangle

#### Scenario: the same row on the commit page

- **GIVEN** the same directory, in the commit page's Unstaged list
- **THEN** it is drawn as a directory there too, by the same rule

#### Scenario: an untracked file is unaffected

- **GIVEN** an untracked *file*
- **THEN** its row is a file row, as it is today

### Requirement: An untracked directory expands to what is inside it

Expanding an untracked directory's row SHALL list the files that staging it
would add, and that listing SHALL be asked for only when the row is expanded and
SHALL be scoped to that directory.

Not by changing what the listing asks for. The whole tree at `-uall` is the seven
seconds this cannot pay; one directory at `-uall` costs what that directory holds,
and `GitWorkingCopy.contents(ofUntrackedDirectory:in:)` already asks exactly
that.

#### Scenario: opening the row

- **WHEN** an untracked directory's row is expanded
- **THEN** the files inside it appear beneath it

#### Scenario: nothing is read until it is opened

- **GIVEN** a working copy with untracked directories holding thousands of files
- **WHEN** the changes are listed and nothing is expanded
- **THEN** nothing inside any of those directories has been listed

#### Scenario: staging the folder is unchanged

- **WHEN** an untracked directory's row is staged, expanded or not
- **THEN** the whole directory is staged, as it is today

#### Scenario: a file inside it can be opened

- **GIVEN** an expanded untracked directory
- **WHEN** a file under it is activated
- **THEN** that file opens, as any other row in the list does

### Requirement: A changed row says how much changed

Every row standing for a changed file SHALL carry the number of lines added and
removed, and every row standing for a folder SHALL carry the sum of those
numbers for what is under it.

Without it, a one-line change and a rewrite are the same row, and the only way
to tell them apart is to open both.

#### Scenario: a file in a commit

- **GIVEN** a commit in which a file gained 12 lines and lost 3
- **THEN** its row says 12 added and 3 removed

#### Scenario: a folder holds the sum

- **GIVEN** a folder row holding three changed files
- **THEN** it says the total added and removed beneath it

#### Scenario: a file with no line changes

- **GIVEN** a change git reports no line counts for — a binary file, a mode
  change, a pure rename
- **THEN** the row says nothing about lines rather than saying zero

#### Scenario: the working copy too

- **GIVEN** an edited file in the working copy
- **THEN** its row in the changes view carries its counts, staged or unstaged

### Requirement: Asking how much changed does not make a repository slow to read

The line counts SHALL be asked for once per set of changes rather than once per
row, and SHALL NOT be asked for again while neither the commit nor the working
copy has moved.

A diffstat has no scope to be cut down to — unlike the untracked directory
listing, which is affordable precisely because it is per directory and on
demand. So the cost has to be bounded by asking rarely.

#### Scenario: one question for a whole commit

- **WHEN** a commit's changes are listed with their counts
- **THEN** the counts came from one command, not one per file

#### Scenario: nothing has moved

- **GIVEN** a commit already listed with its counts
- **WHEN** the same commit is shown again
- **THEN** the counts are not asked for again
