# Pull Requests

## ADDED Requirements

### Requirement: The list says it is asking GitHub with a hairline under its header

The pane SHALL show, while the pull-request list is being read, a two-point
strip at the seam under its header with a run of the accent colour sweeping
along it, and SHALL NOT cover or dim the pane. When nothing is showing
beneath the strip the pane SHALL say what it is waiting for in a small
centred sentence and SHALL add that it is still waiting after five seconds;
when rows are showing beneath, the pane SHALL keep them on screen and show
the sweep alone.

Reported 2026-09-11: the boxed spinner in the middle of an empty pane. Chosen
2026-09-12 over four other treatments, for the pane that already has rows.

#### Scenario: The list loading into an empty pane

- **GIVEN** the pull-request list opened with `gh` installed
- **WHEN** GitHub has not yet answered
- **THEN** a sweep runs under *Only me / My teams too*, the sentence *Asking GitHub…* sits centred beneath, and the rows replace the sentence when they arrive

#### Scenario: A refresh with rows showing

- **GIVEN** the list showing three pull requests
- **WHEN** the refresh glyph is pressed
- **THEN** the three rows stay on screen, the sweep runs under the header, and no sentence is drawn over the rows

#### Scenario: A long wait

- **GIVEN** an empty list waiting on GitHub
- **WHEN** five seconds pass without an answer
- **THEN** the sentence says it is still waiting, and the sweep continues
