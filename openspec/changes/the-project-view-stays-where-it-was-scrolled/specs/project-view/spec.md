# Project View

## ADDED Requirements

### Requirement: A rebuild of the tree keeps where it was scrolled

The navigator SHALL keep where its tree was scrolled across every rebuild that
remembers what was expanded and selected — by the row at the top of the view
and its offset, not by a pixel — and SHALL put it back after the expansion and
the selection. A session event, a watched directory changing,
a settings change and the reload when the window comes forward are all such
rebuilds. Opening a different project or marking a subproject are not: the tree
becomes a different tree, and starts at the top.

Reported 2026-09-09: the project view scrolled to the top, seemingly at
random, while the Claude Sessions part of the tree was being read and a session
was taking screenshots — which is a session event every few seconds.

#### Scenario: A session works while its files are being read

- **GIVEN** the tree scrolled so that a session's files are in view, with rows
  above them out of view
- **WHEN** a hook event changes which sessions are running, and the sessions
  root is rebuilt
- **THEN** the row that was at the top of the view is at the top of the view,
  at the same offset

#### Scenario: A row appears above the reader

- **GIVEN** the tree scrolled to a row well below the top
- **WHEN** a rebuild adds a row above it
- **THEN** the same row is still at the top of the view, one row further into
  the document

#### Scenario: The row that was at the top is gone

- **GIVEN** the tree scrolled to a row well below the top
- **WHEN** a rebuild removes that row
- **THEN** the view stays at the same offset, clamped to the tree's new length,
  rather than returning to the top

#### Scenario: Reading the place from a driven run

- **GIVEN** a driven run with a tree longer than its pane
- **WHEN** the tree steps `end,place,reload,place` run
- **THEN** the two `place` lines print the same top row and offset
