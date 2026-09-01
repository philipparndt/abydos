## ADDED Requirements

### Requirement: The backlog pane is drawn below the strip that names it
The backlog pane's own header SHALL be laid out below the panel's tab strip, whatever order the pane and the strip are sized in, and at every zoom.

#### Scenario: Opening the backlog
- **WHEN** the backlog pane is shown in the bottom panel
- **THEN** its view control and its refresh verb are below the tab strip, overlapping neither the tabs nor the strip's trailing controls

#### Scenario: The strip's height changes
- **WHEN** the zoom changes while the backlog pane is showing, so the strip grows
- **THEN** the pane is still below it
