## ADDED Requirements

### Requirement: The changes tree keeps its selection when a row is opened
Expanding a folder in the commit page's changes tree SHALL keep that folder selected, including when the folder is an untracked one drawn as a compacted chain.

#### Scenario: Opening an untracked folder with the keyboard
- **WHEN** an untracked folder row is selected in the changes tree and → is pressed
- **THEN** the folder opens, showing what is under it, and the folder row is still the selection

### Requirement: Staging keeps a usable selection
Staging or unstaging from the changes tree SHALL leave the selection on a row that still exists, so that the keyboard can carry on from where it was.

#### Scenario: Staging with the keyboard
- **WHEN** a file is staged from the changes tree
- **THEN** the selection lands on the neighbouring row rather than being lost, and ↑ and ↓ move from it
