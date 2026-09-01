## ADDED Requirements

### Requirement: The review page's header controls follow the zoom
The pull-request review page's header controls — the review and check-out verbs, the read and whole-file switches, and the view-mode control — SHALL take their size from the zoom in force and SHALL change size when it changes.

#### Scenario: Reviewing at a large zoom
- **WHEN** the zoom is raised with a pull request open
- **THEN** every control in the header grows with the title and the file list beside them

### Requirement: The pull-request list's controls follow the zoom
The pull-request list's scope control and the glyph beside it SHALL take their size from the zoom in force and SHALL change size when it changes.

#### Scenario: The list at a large zoom
- **WHEN** the zoom is raised with the pull-request list showing
- **THEN** `Only me` / `My teams too` and the glyph beside them are at the new size, and the rows and the controls read as one pane
