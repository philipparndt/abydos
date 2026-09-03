## ADDED Requirements

### Requirement: A row is named by where it is when nothing has said its id

Every session in the register MUST have an identity that tells it apart from
every other, whether or not it has announced a session id. A record seeded from
a tmux window's badge has no id — `isSeeded` is *defined* as `id.isEmpty` — so
the identity of such a record SHALL be its tmux session and window index, which
is what the register already keys it by.

Everything that tells rows apart SHALL use that identity and not the id: the
order's final tie-break, the place a row is remembered at, and the question
"which row is this session on".

**This is the fault under three earlier reports of the list jumping about.**
Eight badged windows answered `id` with the same empty string, so the tie-break
called every pair equal and `sorted` was free to swap them on each of the
rebuilds that happen every second; the remembered order remembered one place
for all of them; and the selection resolved to the first of them. Every session
a driven run could create had an id, so no run could reach it.

#### Scenario: six badged windows and nothing heard from any of them

- **GIVEN** six tmux windows with a badge and no hook event for any
- **WHEN** the list is open and rebuilt
- **THEN** the six rows are in window order and stay in it
- **AND** a row selected among them stays selected

### Requirement: The list holds the order it came up in

While the list is open its rows SHALL stay where they are. The order is decided
on the first reading after it opens — the register's own, which is where each
session is rather than when it last spoke — and held from then on. A session
that appears while it is open SHALL be added at the end of its project's rows
rather than in its ordered place, so that nothing already on screen moves.

Reopening the list SHALL decide the order again.

**Why the order cannot simply be computed each time.** It is computed from data
that keeps arriving: a session learns its tmux window and leaves the windowless
tail, a session in another project appears and its group takes its place by
name, the mirror seeds a badged window and drops it a second later. The list is
rebuilt on every hook event and once a second besides, and a row that moves
while somebody is reaching for it cannot be clicked — nor can a highlight be
read, since it travels with its session.

#### Scenario: a session appears while the list is open

- **GIVEN** an open list with three projects in it
- **WHEN** a session starts in a project whose name sorts first
- **THEN** the rows already shown are where they were
- **AND** the new session is at the end

#### Scenario: a session learns where it is

- **GIVEN** an open list holding a session with no tmux window
- **WHEN** an event says which window it is in
- **THEN** its row does not move

#### Scenario: reopening

- **WHEN** the list is closed and opened again
- **THEN** the rows are in the register's order, newcomers included

#### Scenario: a seeded window's session speaks for itself

- **GIVEN** an open list with a row for a badged tmux window nothing has been
  heard from
- **WHEN** that session announces itself and the register replaces the seeded
  record with the real one
- **THEN** the row is where it was, because a place belongs to the window as
  well as to the record speaking for it

### Requirement: The lit rows survive the list being rebuilt

The list SHALL keep its selection and its hover on the same *things* across a
rebuild, never on the same row numbers. It is rebuilt on every hook event and
once a second while anything is working, and a session appearing or ending
renumbers every row after it.

The selection SHALL be re-found by the session's id, and dropped where that
session is no longer listed rather than left on whatever now occupies its
number. The hover SHALL be re-found from where the pointer is at that moment,
because nothing tells the list that what sits under a motionless pointer has
changed.

#### Scenario: a session ends while the list is open

- **GIVEN** a list with the fourth row selected and the pointer on the sixth
- **WHEN** a session in an earlier group ends and the list is rebuilt
- **THEN** the same session is still selected
- **AND** the hover is on whichever row the pointer is now over, or on none

#### Scenario: the selected session goes away

- **GIVEN** a list with a row selected
- **WHEN** that session ends
- **THEN** the selection moves to the first row, and not to a stranger at the
  same number

### Requirement: A remembered selection says that the keys are elsewhere

Where a row is selected and the filter holds the keyboard, the list SHALL draw
that row differently from a row whose selection the keys would act on — as an
outline rather than as a filled band, so that it cannot be confused with the
hover tint, which is visible at the same time.

Pressing ⏎ in the filter SHALL act on the selected row where there is one, and
on the first row shown where there is not.

#### Scenario: reopening the list

- **WHEN** the list is opened again after a row was selected in it
- **THEN** that row is still selected, drawn as an outline
- **AND** the keyboard is in the filter with what was typed before selected
- **AND** ⏎ chooses that row

#### Scenario: the rows take the keyboard

- **GIVEN** a selection drawn as an outline
- **WHEN** ↓ moves the keyboard into the rows
- **THEN** the selection is drawn as a filled band from then on
