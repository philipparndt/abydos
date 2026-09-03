# Git log page tree

## Purpose

How a commit's changed files are arranged on the log page: as the flat list it has always been, or as the folder tree the sidebar has grouped them into since it was written — a choice that is remembered, keeps the selection across it, and opens whole to `*`.
## Requirements
### Requirement: The log page arranges a commit's files by folder or as a list

The log page's changes view SHALL offer both a flat list of the files a commit
touched and a tree of the folders holding them, and the flat arrangement SHALL
show what it shows today, row for row.

Thirty files across six modules is thirty rows with no shape in a view that has
room for one. The sidebar has grouped them since it was written.

#### Scenario: arranged by folder

- **GIVEN** a commit touching `Sources/A.swift` and `Tests/B.swift`
- **WHEN** the folder arrangement is chosen
- **THEN** the files appear under `Sources` and `Tests`

#### Scenario: arranged as a list

- **WHEN** the flat arrangement is chosen
- **THEN** the rows are the files, in the order they are in today, with no
  folders

#### Scenario: the same files either way

- **WHEN** the arrangement is changed
- **THEN** the files shown are the same files, and only their arrangement differs

### Requirement: The arrangement is remembered

The choice SHALL be kept between sessions and SHALL apply to the next commit
opened.

Choosing again for every commit is choosing nothing.

#### Scenario: the next commit

- **GIVEN** the folder arrangement chosen
- **WHEN** another commit is opened
- **THEN** it is arranged by folder

#### Scenario: the next session

- **GIVEN** the folder arrangement chosen
- **WHEN** the window is closed and opened again
- **THEN** it is still arranged by folder

### Requirement: A file stays selected across a change of arrangement

Changing the arrangement SHALL keep the selection on the same file, and SHALL
keep showing that file's diff.

The two arrangements hold the same files at different depths, so a selection
held as a row number lands on a different file — which is worse than losing it.

#### Scenario: the selection follows the file

- **GIVEN** `Sources/A.swift` selected in the flat list
- **WHEN** the folder arrangement is chosen
- **THEN** `Sources/A.swift` is selected, under `Sources`

#### Scenario: the diff does not change

- **WHEN** the arrangement is changed with a file selected
- **THEN** the diff on screen is still that file's

### Requirement: The star key opens the whole tree

Pressing `*` with the changes view focused SHALL expand every folder in it,
whatever row the selection is on, and SHALL keep the selection.

#### Scenario: from any row

- **GIVEN** a folder arrangement with folders shut, and the selection part-way
  down
- **WHEN** `*` is pressed
- **THEN** every folder is open and the same row is selected

#### Scenario: nothing to open

- **GIVEN** the flat arrangement, which has no folders
- **WHEN** `*` is pressed
- **THEN** nothing happens and nothing is lost

### Requirement: A folded merge draws none of its branch's lanes
When a merge is folded, the graph SHALL be laid out over the rows that are drawn, so that no lane belonging to a hidden commit appears. No line SHALL be drawn that has no visible commit to start from.

#### Scenario: Folding a merge with a branch under it
- **WHEN** a merge is folded on the log page
- **THEN** the lanes of the branch it brought in are gone from every row below, and every line still drawn begins at a commit that is on screen

#### Scenario: Unfolding puts it back
- **WHEN** the same merge is unfolded again
- **THEN** the graph is the one that was there before it was folded

