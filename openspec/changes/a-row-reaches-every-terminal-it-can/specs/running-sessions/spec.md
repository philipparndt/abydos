## MODIFIED Requirements

### Requirement: The popover lists every running session, this project first

Clicking the pill SHALL open a popover anchored to it listing every running
session on the machine, grouped by project. The window's own project SHALL be
the first group; the rest SHALL follow with the most recently heard first. A
group SHALL be titled with the last component of the project's path and its
parent, home-relative — not its slug.

A row SHALL be one line: the session's status badge; the tmux window's name and
index when the hook could say them, otherwise the last announced line; the last
announced line after the name, dimmed, when the name took the title; and how
long ago the last event was. An unknown session SHALL be drawn hollow and
labelled by its silence. A session the app cannot reach SHALL be drawn dimmed
and marked *elsewhere* before its age.

The popover SHALL carry a filter field above the rows, which has the keyboard
when the popover opens, narrows the rows to those whose project, window name or
last line contain what is typed, hides groups left empty, and chooses the first
row still shown on ⏎. The rows SHALL scroll inside a popover whose height is
bounded, so a dozen sessions are a dozen rows.

#### Scenario: two projects

- **GIVEN** the window on `abydos`, a session working there, and a session needing input in `abydos-examples`
- **WHEN** the pill is clicked
- **THEN** the first group is `abydos` and the second `abydos-examples`, each with its row

#### Scenario: a session outside tmux

- **GIVEN** a session announced with no tmux place
- **THEN** its row is titled by its last announced line, and carries no window number

#### Scenario: a session that has gone quiet

- **GIVEN** a working session silent for two minutes
- **THEN** its row is drawn hollow, reads its last line, and says how long it has been silent

#### Scenario: typing a filter

- **GIVEN** twelve sessions across four projects
- **WHEN** `screen` is typed into the filter
- **THEN** only the rows whose project, window name or last line contain `screen` are shown, under their own group titles, and ⏎ chooses the first of them

#### Scenario: a session in another app's terminal

- **GIVEN** a session with neither a tab identity the app holds nor a tmux place
- **THEN** its row is dimmed and reads *elsewhere* before its age

### Requirement: A row takes you to the session, or hands you the way back to it

Clicking a row SHALL bring the session's terminal in front wherever the app
holds it, in this order: the tab whose identity the session named, in this
window or in another, is activated and its window brought forward; a session in
the tmux session this panel mirrors has its window and its pane selected; a
session in another tmux session has this panel's tmux client switched to it, or
a `tmux` tab attached to it when the panel has none, and then its window and
pane selected. None of these SHALL require the `tmux` tab to be in front.

Clicking a row the app cannot reach — no tab identity it holds, no tmux place —
SHALL copy the session's resume command to the pasteboard and SHALL say so.

#### Scenario: a row in one of this window's own tabs

- **GIVEN** a session started in the panel's second `Local` tab, while the `tmux` tab is in front
- **WHEN** its row is clicked
- **THEN** the second `Local` tab is in front with the keyboard

#### Scenario: a row in another window's tab

- **GIVEN** two windows, and a session in a tab of the second
- **WHEN** its row is clicked in the first
- **THEN** the second window comes forward with that tab in front

#### Scenario: a row in the mirrored session

- **GIVEN** the window mirroring tmux session `abydos` and a row for its window 2, pane `%7`
- **WHEN** the row is clicked
- **THEN** the panel shows tmux window 2 with pane `%7` selected

#### Scenario: a row in another tmux session

- **GIVEN** the panel mirroring `abydos` and a row for window 3 of session `platform`
- **WHEN** the row is clicked
- **THEN** the panel's client is switched to `platform` and window 3 is selected

#### Scenario: a row elsewhere

- **GIVEN** a row with no tab identity the app holds and no tmux place
- **WHEN** the row is clicked
- **THEN** `claude --resume <id>` is on the pasteboard, and a toast says it was copied
