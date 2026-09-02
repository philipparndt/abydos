## ADDED Requirements

### Requirement: A changed row is marked
A row in the project tree whose file or folder has a version-control state SHALL draw a mark at its trailing edge in that state's colour, so that a change is visible as a mark and not only as the shade of the name.

#### Scenario: A changed file
- **WHEN** a file has been modified, added, or is untracked
- **THEN** its row carries a mark in that state's colour, and the mark is the same colour the name is drawn in

#### Scenario: A folder holding a change
- **WHEN** a folder contains a change, whether it is open or shut
- **THEN** its row carries the mark too, so a collapsed folder says that there is something inside it

#### Scenario: Nothing to say
- **WHEN** a file is unmodified, or ignored
- **THEN** its row draws no mark, because a mark on nearly every row is not a mark

#### Scenario: A long name
- **WHEN** a name is too long for its row
- **THEN** it is truncated before it reaches the mark rather than drawn underneath it
