## ADDED Requirements

### Requirement: The log page's controls follow the zoom
The log page's search field and its scope control SHALL take their size from the zoom in force, and SHALL change size when it changes, so that they are never at system size beside commit rows that have grown.

#### Scenario: Zooming with the log page open
- **WHEN** the zoom is raised while the log page is showing
- **THEN** the search field and the `Whole Repository` / `This File` control grow with the rows, and the field's placeholder is in the same size of type as the rows beside it

### Requirement: A commit row is tall enough for both its lines
A commit row SHALL be as tall as the two lines it draws — the subject and the line under it carrying the short hash — plus its paddings, at every zoom step. The height SHALL be derived from the measured line heights rather than from a constant chosen at one scale.

#### Scenario: The short hash at a large zoom
- **WHEN** the log page is drawn at any of the nine zoom steps
- **THEN** the whole of the second line is inside the row, and no part of the short hash is clipped by the row's edge

#### Scenario: The height is re-taken when the zoom changes
- **WHEN** the zoom changes while a log page is open
- **THEN** the table's row height is recomputed and the rows are re-laid-out, rather than keeping the height read when the table was built

### Requirement: The commit page's controls follow the zoom
The commit page's section buttons, its message controls and the chevron that expands the description SHALL take their size from the zoom in force and SHALL change size when it changes.

#### Scenario: Staging at a large zoom
- **WHEN** the zoom is raised on the commit page
- **THEN** `Stage` and `Unstage` grow with their words rather than keeping their words in a shape that stayed the size it was

#### Scenario: The message controls
- **WHEN** the zoom is raised on the commit page
- **THEN** `Draft`, `Commit`, `Push` and the description chevron are all at the new size

### Requirement: The commit page's detail area returns from a presentation scale
The commit page's detail area is divided in points, and those points are a function of the scale. When the scale changes — including leaving presentation mode — the division SHALL be recomputed rather than left where the previous scale put it.

#### Scenario: Coming back from a talk
- **WHEN** presentation mode is switched off while the commit page is open
- **THEN** the detail area is the size the working zoom calls for, not the size the presentation zoom left behind
