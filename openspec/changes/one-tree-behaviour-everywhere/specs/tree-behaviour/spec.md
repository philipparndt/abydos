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

### Requirement: A selection survives the row moving out from under it
When the row that is selected stops being in the list — staged, unstaged, filtered away, or deleted — the tree SHALL select its nearest surviving neighbour rather than leaving nothing selected.

#### Scenario: Staging the selected file
- **WHEN** the selected file in the changes tree is staged, so its row leaves the unstaged section
- **THEN** the neighbouring row is selected, and the arrow keys carry on from there

### Requirement: Every tree draws the app's selection
A selected row SHALL be drawn in the app's own selection — a rounded, inset shape in the palette's selection colour, strong while the tree has the keyboard and quiet while it does not. No tree SHALL leave the system to paint its own selection band.

#### Scenario: A selected row in any tree
- **WHEN** a row is selected in the changes tree, the project tree, the branches tree or the pull-request file tree
- **THEN** the shape and the colour are the same in all four, and are the palette's rather than the system's

#### Scenario: The keyboard is somewhere else
- **WHEN** a tree holds a selection while the keyboard is in another pane
- **THEN** the selection is drawn in the quiet colour, saying where you were without claiming where your keys are going
