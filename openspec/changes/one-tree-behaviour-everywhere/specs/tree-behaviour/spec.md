## ADDED Requirements

### Requirement: A selection survives opening and closing a row
Expanding or collapsing a row in any tree SHALL leave the selection where it was. This holds when the expansion causes the tree to be rebuilt, and it holds when the rebuild changes how rows are grouped.

#### Scenario: Expanding the selected folder
- **WHEN** a folder row is selected and → is pressed
- **THEN** the folder opens and the same row is still selected, so the next arrow key moves from it

#### Scenario: Expanding a row that was compacted
- **WHEN** the selected row is a chain of folders drawn as one row, and it is expanded
- **THEN** the selection is still on a row the person can see, and the arrow keys still move from it

### Requirement: A restore that finds nothing falls back and says so
When a tree rebuilds and the row that was selected no longer exists, the tree SHALL select the nearest surviving row above it rather than leaving nothing selected, and SHALL record that it had to.

#### Scenario: The selected row has gone
- **WHEN** a rebuild removes the row that was selected
- **THEN** the nearest surviving row above it is selected, and the log carries a line saying the restore missed

#### Scenario: A restore never jumps to the top
- **WHEN** a restore cannot find its row in a long list somebody was reading the middle of
- **THEN** the selection lands near where it was and never on the first row
