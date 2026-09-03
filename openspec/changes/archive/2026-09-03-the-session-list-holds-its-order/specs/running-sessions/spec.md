## MODIFIED Requirements

### Requirement: The popover lists every running session, this project first

Clicking the pill SHALL open a popover anchored to it listing every running
session on the machine, grouped by project. The window's own project SHALL be
the first group; the rest SHALL follow ordered by name, the last component of
each project's path, with the slug breaking a tie. A group SHALL be titled with
the last component of the project's path and its parent, home-relative — not its
slug.

Within a group, sessions SHALL be ordered by where they are and never by when
they last spoke: the tmux session's name, then the window's index, then the
sessions with no tmux window at all. Every comparison SHALL end in a tiebreak
that cannot move — the session's own id — so that no two rows can be called
equal and swap on a redraw.

**A row SHALL keep its place for as long as its session exists.** The list is
rebuilt on every hook event and once a second by the staleness clock; an order
that depends on time therefore moves under the pointer, and a row that moves
while somebody is reaching for it cannot be clicked.

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

#### Scenario: a session speaking does not move its project

- **GIVEN** three projects in the list, the window's own first and two others after it
- **WHEN** a session in the last of them sends an event
- **THEN** the groups are in the same order they were in

#### Scenario: a session speaking does not move its row

- **GIVEN** two sessions in one project, neither in a tmux window
- **WHEN** the second sends an event
- **THEN** the two rows are in the same order they were in

#### Scenario: windows in tmux order

- **GIVEN** one project holding windows 5, 1 and 3 of one tmux session, and a session in no window
- **THEN** the rows read 1, 3, 5, and then the session with no window

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
