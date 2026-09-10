# folder-diff Specification

## Purpose
TBD - created by archiving change two-files-or-two-folders-compare-side-by-side. Update Purpose after archive.
## Requirements
### Requirement: Two folders are shown as two trees aligned by relative path

A folder diff SHALL show A and B as two trees, side by side, in which every
relative path present on either side has one row at the same height in both,
and a folder expands or collapses on both sides at once. Rows are listed one
directory at a time as the walk reaches them, so a large tree is walkable
before it is fully listed, and the counts say `listing…` until it is done.

The trees follow the one tree behaviour `tree-behaviour` describes.

#### Scenario: a file on one side only

- **GIVEN** `Package.resolved` in A and not in B
- **WHEN** the trees are drawn
- **THEN** A has the row and B has an empty row at the same height

#### Scenario: expanding a folder

- **WHEN** `Sources/AbydosKit` is expanded on the right
- **THEN** it is expanded on the left too, and its children are aligned

### Requirement: A row is different, equal, unmatched or ignored, and the cost of knowing which is bounded

Every file row SHALL be in one of four states — *different*, *equal*,
*unmatched* (present on one side only) or *ignored* — and a matched file SHALL
start *unknown*. Sizes decide at once: two files of different sizes are
*different*. Files of equal size are compared by bytes on a background queue,
in chunks, stopping at the first difference, and the row takes its state when
the answer arrives. Answers are cached by path, size and modification date on
both sides, so re-reading after an *Apply* compares only what changed.

A folder row's state follows its children: *different* if any child is not
*equal* or *ignored*.

*Ignored* is decided by either side's `.gitignore` chain and by the built-in
list the navigator already tints as build output; an ignored row is greyed,
not hidden, and its tip names which rule ignored it.

#### Scenario: sizes differ

- **GIVEN** `README.md` of 28 KB in A and 31 KB in B
- **WHEN** the row is listed
- **THEN** it is *different* at once, with no read of either file

#### Scenario: sizes agree

- **GIVEN** `Rope.swift` of 40 KB on both sides, differing in one byte at the end
- **WHEN** the row is listed
- **THEN** it is *unknown* until the comparison ends, and *different* then

#### Scenario: ignored on one side

- **GIVEN** `build/` matched by A's `.gitignore` and not by B's
- **THEN** the row is *ignored* and greyed, and its tip names A's rule

### Requirement: The trees follow the folders as they change on disk

A folder diff over folders on disk SHALL stay current while it is open: a file
written, added, removed or renamed on either side moves, adds or removes its
row and re-decides its state without the page being reopened. Only the
directories an event names are listed again, and a matched file whose size and
modification date are unchanged is not compared again. A side that is a
folder at a commit does not change and is not watched.

#### Scenario: a file saved in another window

- **GIVEN** a folder diff in which `Settings.swift` is *equal*
- **WHEN** A's `Settings.swift` is saved with a change
- **THEN** its row becomes *different*, and no other file is read

#### Scenario: a build writes into one side

- **WHEN** a build writes two thousand files under B's `build/`
- **THEN** `build/` is listed again once for the batch, its rows are *ignored*,
  and the counts say `listing…` only while that runs

### Requirement: Equal rows are hidden until asked for, and the names can be filtered

Rows that are *equal* SHALL be hidden by default, with their count in the
title — `13 Equal (not shown)` — and a switch that shows them. A filter field
over the page SHALL narrow both trees to rows whose name contains the text,
keeping the folders that lead to them.

#### Scenario: equal hidden

- **WHEN** a folder diff has 13 equal files
- **THEN** none of them is listed and the title says `13 Equal (not shown)`

#### Scenario: filter

- **WHEN** `Terminal` is typed into the filter
- **THEN** only rows whose name contains it remain, under their folders

### Requirement: A file row opens its file diff in the same tab

Clicking a *different* file row SHALL open the file diff of that pair in the
same tab, with a way back to the trees — which come back as they were left:
expanded where they were expanded, the row selected, scrolled to where they
were; an *unmatched* file opens on its own
side with the other side saying the file is absent; a folder row expands.

#### Scenario: a different file

- **WHEN** `Settings.swift`, marked *different*, is double-clicked
- **THEN** the tab shows the file diff of A's and B's `Settings.swift`, and
  back returns to the trees at the same row

### Requirement: Copies and deletions are marked in the gutter and done together on Apply

The gutter between the trees SHALL offer, on every row that is not *equal*,
*copy to B*, *copy to A* and *delete*, and marking one SHALL change nothing on
disk: the page counts `n items to copy` and *Apply…* lists every marked
operation, with its direction, before doing them together.

Before a file is overwritten or removed it SHALL be moved to the Trash, so
that every apply can be undone with the Finder's *Put Back*. A side that is a
folder at a commit is read-only: its rows offer only copies out of it, and the
apply never writes to it. The rows an apply touched are refreshed by the
changes it made on disk, as any other change is.

#### Scenario: three marks, one apply

- **GIVEN** `Package.swift` marked *copy to A*, `Sources/AbydosKit/Text/UndoTree.swift`
  marked *copy to A*, and `Package.resolved` marked *delete*
- **WHEN** *Apply…* is pressed
- **THEN** a sheet lists the three with their directions, and confirming copies
  the two and removes the third, after moving A's `Package.swift` and
  `Package.resolved` to the Trash

#### Scenario: a read-only side

- **GIVEN** B is the tree at a commit
- **WHEN** a row's gutter is opened
- **THEN** *copy to B* and *delete on B* are not offered

#### Scenario: nothing marked

- **WHEN** no row is marked
- **THEN** *Apply…* is disabled and the count says nothing

