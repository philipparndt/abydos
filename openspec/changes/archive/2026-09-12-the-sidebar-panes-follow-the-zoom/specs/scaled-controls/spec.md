# Scaled Controls

## ADDED Requirements

### Requirement: The sidebar's own fields, labels and switches are members

The library SHALL count among its members the Structure pane's filter field
and placeholder label, the Scratches pane's search field and empty label, the
Backlog pane's two switches and its refresh button, and the pull-request
list's trouble text — measured members for the fields and labels, drawn
members for the switches and the button — so that each follows the zoom
without the pane that owns it being told.

Reported 2026-09-11 with four screenshots: each of these at the size it had
at 1.0 while the controls around it had grown.

#### Scenario: The Structure pane at a large zoom

- **GIVEN** the Structure pane showing with no file open
- **WHEN** the zoom is raised
- **THEN** *Filter symbols* and *No file open* are at the new size on the next display pass

#### Scenario: The Scratches pane at a large zoom

- **GIVEN** the Scratches pane showing
- **WHEN** the zoom is raised
- **THEN** *Search scratches* is at the size of the two buttons beside it, and the section header and rows are re-measured

#### Scenario: The Backlog pane's switches

- **GIVEN** the Backlog pane showing its board
- **WHEN** the zoom is raised
- **THEN** *List / Board* and *Backlog / OpenSpec* grow as one shape with their words, as *Only me / My teams too* does in the pull-request list, and the bezel is not the source of the size
