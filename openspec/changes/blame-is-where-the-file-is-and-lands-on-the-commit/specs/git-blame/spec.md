## ADDED Requirements

### Requirement: The blame column says who last touched each line

The editor SHALL show, on request and per file, a column beside the code
with the author and the age of the commit that last touched each line, with
a line that is not committed marked as such. It SHALL be read from git for
the file as it stands on disk, so uncommitted lines are not attributed to
whoever last committed there.

#### Scenario: a committed file with one edit

- **GIVEN** a file committed by one author and then edited on one line
- **WHEN** blame is shown
- **THEN** every line but the edited one carries the author and the age, and
  the edited one is marked uncommitted

### Requirement: Blame is reachable from the file, wherever the file is

Blame SHALL be reachable from the file's context menu in the project tree,
from the tab's menu, and from the palette by name, as well as from the
editor's gutter menu and ⌥⌘B. From the tree and the tab, *Blame* SHALL open
the file if it is not open and turn the column on.

A colleague could not find it: the tree and the tab are where a question
about a file is asked, and both IDEs he knows put blame there.

#### Scenario: from the tree

- **GIVEN** a file not open
- **WHEN** *Blame* is chosen on its row
- **THEN** the file opens, pinned, with the blame column on

#### Scenario: from the palette

- **WHEN** `blame` is typed into the palette
- **THEN** the command is offered

### Requirement: A blame entry leads to its commit

Clicking a blame entry SHALL open the log page scoped to the file, at that
commit, with the commit's row selected, so its message and its diff of the
file are on screen. Clicking an uncommitted line SHALL say it is not
committed yet and go nowhere.

#### Scenario: a click

- **GIVEN** the blame column on
- **WHEN** an entry with a commit is clicked
- **THEN** the log page shows that commit's row selected, scoped to the file

#### Scenario: an uncommitted line

- **WHEN** an uncommitted line's entry is clicked
- **THEN** a toast says the line is not committed yet and no page opens

### Requirement: Moved code keeps its author, and ignored revisions are ignored

Blame SHALL ask git to follow moves and copies (`-M -C`), and SHALL pass the
repository's `.git-blame-ignore-revs` when the file exists at the root, so a
block moved within a file is attributed to who wrote it and a formatting
commit listed there does not own every line. A `blame.ignoreRevsFile` set in
git's configuration is git's own and SHALL NOT be repeated.

#### Scenario: a moved block

- **GIVEN** a block written by one author and moved within the file by another
- **WHEN** blame is shown
- **THEN** the block's lines carry the first author

#### Scenario: a formatting commit

- **GIVEN** a commit that re-indented the file, listed in `.git-blame-ignore-revs`
- **WHEN** blame is shown
- **THEN** the lines carry the commits before it
