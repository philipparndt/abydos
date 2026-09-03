## ADDED Requirements

### Requirement: The backlog pane is drawn below the strip that names it
The backlog pane's own header SHALL be laid out below the panel's tab strip, and SHALL keep its height — or be hidden whole — through every change of zoom, theme or presentation mode while the pane is showing, whether the project keeps its work in `.abydos/backlog`, in `openspec/changes`, or in both. A header of no height whose controls still draw is how the controls came to sit over the strip.

#### Scenario: Opening the backlog
- **WHEN** the backlog pane is shown in the bottom panel
- **THEN** its view control and its refresh verb are below the tab strip, overlapping neither the tabs nor the strip's trailing controls

#### Scenario: The zoom changes while the pane is showing
- **GIVEN** a project whose work is in `openspec/changes` and not in `.abydos/backlog`
- **WHEN** the zoom, the theme or presentation mode changes while the backlog pane is showing
- **THEN** the header is still its full height, directly below the strip, and its controls are inside it
