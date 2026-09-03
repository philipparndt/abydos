# running-sessions Specification

## Purpose
TBD - created by archiving change the-panel-counts-the-running-sessions. Update Purpose after archive.
## Requirements
### Requirement: The register remembers what each running session last said

The app SHALL keep, for every running session it has heard of, the status the
hook last derived, the tmux session and window the hook ran in when it did,
the last line the hook announced, and the time of the last event. A session is
running from its `SessionStart`, or from the first event heard from it, until
its `SessionEnd`.

The register SHALL say whether an event moved the shown answer — a session
appearing or ending, a status changing, a turn finishing — and SHALL say that
nothing moved for a tool-use event from a session whose status it already had.
The second half is what makes listening affordable: a working session sends a
tool-use event dozens of times a minute.

#### Scenario: a status change is a move

- **WHEN** a session known to be working sends a `Notification` that wants an answer
- **THEN** the register records it as needing input, and says the answer moved

#### Scenario: a tool use from a known working session is not

- **WHEN** a session known to be working sends a `PostToolUse` with status `working`
- **THEN** the register keeps its record, and says nothing moved

#### Scenario: the last line is kept

- **WHEN** a session announces `zsh needs you` with a message naming the permission asked
- **THEN** the register holds that line and that message against the session, with the time

### Requirement: The pill counts the working and the waiting, and nothing else

The terminal panel's title bar SHALL show, left of the tmux session tag, a pill
with two counts: how many running sessions on the machine are working, in the
tabs' working colour, and how many need input, in the tabs' needs colour. A
finished session SHALL NOT be counted. A working session whose last event is
older than the tabs' staleness bound SHALL be counted under neither.

The pill SHALL NOT be drawn when the register holds no session. Where the strip
is too narrow for the tmux tag to carry the session's name, the pill SHALL
drop its digits and keep its dots.

#### Scenario: three working, one waiting, one finished

- **GIVEN** five running sessions: three working, one needing input, one done
- **WHEN** the strip is drawn
- **THEN** the pill reads a working count of 3 and a needs count of 1

#### Scenario: a working session falls silent

- **GIVEN** one working session whose last event was 31 seconds ago
- **WHEN** the strip is redrawn
- **THEN** the working count is 0, and the pill is still drawn because the session is still running

#### Scenario: nothing running

- **GIVEN** an empty register
- **THEN** no pill is drawn

#### Scenario: a narrow strip

- **GIVEN** a strip under the width at which the tmux tag drops the session's name
- **THEN** the pill shows its two dots without digits

### Requirement: The pill redraws when the answer moves, and ticks only while something works

The pill SHALL redraw when the register says an event moved the shown answer,
and SHALL NOT redraw for an event that did not. While at least one session is
working, the pill SHALL re-evaluate staleness once a second; when none is, no
timer SHALL be running.

#### Scenario: a burst of tool-use events

- **GIVEN** a working session sending a tool-use event every two seconds
- **WHEN** a minute passes
- **THEN** the pill was not redrawn for any of them

#### Scenario: the last working session finishes

- **GIVEN** one working session and the staleness timer running
- **WHEN** it sends `Stop` and the register records it as done
- **THEN** the pill redraws once, and the timer is stopped

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

### Requirement: The mirrored tmux session seeds what the hook has not yet said

The mirror SHALL seed the register from the windows of the tmux session this
window mirrors: a window whose `@ai_status` names a state, and whose session the
register has not heard from, is given a record with that state and no session
id, so that a session running before the app launched is counted and can be
revealed. The record SHALL be replaced by the hook's own at the session's next
event.

A seeded record SHALL be filed under the directory the window's pane is in,
which tmux reports as `pane_current_path` — not under the project this window
is on. A tmux session is somebody's workspace and its windows sit in many
projects; filing them all under one put `screencasts` in `~/dev/oss`.

Nothing SHALL be seeded for sessions outside the mirrored tmux session; those
appear at their next event.

#### Scenario: a window in another project

- **GIVEN** the window on `~/dev/oss/abydos`, mirroring a tmux session whose window 2 is badged `working` and whose pane is in `~/dev/vehub/screencasts`
- **WHEN** the mirror reads the session's windows
- **THEN** the seeded record is grouped under `screencasts` in `~/dev/vehub`, not under `abydos`

#### Scenario: a session older than the app

- **GIVEN** a tmux window whose `@ai_status` is `needs` and no record for it
- **WHEN** the mirror reads the session's windows
- **THEN** the pill's needs count includes it, and its row reveals the window

#### Scenario: the hook catches up

- **GIVEN** such a seeded record
- **WHEN** the session's next hook event arrives with its id
- **THEN** there is one record for it, the hook's, and the counts do not change

### Requirement: A driven run can be told what to show

A driven run SHALL accept `--claude-running <id>[@<seconds>][:<status>]`, more
than once, to put records in the register without a hook, so the pill and the
popover can be photographed and read. The status defaults to `working`. A
driven run SHALL still subscribe to no hook, as the screenshots capability
requires.

#### Scenario: two states in one picture

- **GIVEN** a driven run given `--claude-running a:working --claude-running b:needs`
- **THEN** the pill reads 1 and 1, and the popover has two rows in the run's project

#### Scenario: a session appearing while somebody watches

- **GIVEN** a driven run given `--claude-running a@3`
- **WHEN** three seconds pass
- **THEN** the pill appears with a working count of 1

### Requirement: A nudge does not wake a finished session

The register SHALL leave a `done` record as it is when a `Notification` that is
only Claude's idle nudge, or a `SubagentStop`, arrives for that session, SHALL
report the event as no move, and SHALL NOT let it be announced in the corner. The
register SHALL be able to say so before the event is recorded, so the corner can
ask.

This is the rule the hook already keeps for a session in tmux, where the window's
own badge says `done`; outside tmux the hook has no memory, and the register is
it. A nudge for a session that was working, or a notification that is a real
question — a permission prompt, `agent_needs_input` — is unaffected.

#### Scenario: the idle nudge a minute after an answer

- **GIVEN** a session outside tmux whose record says `done`
- **WHEN** a `Notification` of type `idle_prompt` arrives for it, with status `needs`
- **THEN** the record still says `done`, the pill's counts do not move, and no toast is raised

#### Scenario: a subagent finishing after the turn ended

- **GIVEN** a session whose record says `done`
- **WHEN** a `SubagentStop` arrives for it
- **THEN** the record still says `done` and nothing is announced

#### Scenario: a nudge for a session that was working

- **GIVEN** a session whose record says `working`
- **WHEN** a `Notification` of type `idle_prompt` arrives for it, with status `needs`
- **THEN** the record says `needs`, and the row turns amber

#### Scenario: a real question after a finished turn

- **GIVEN** a session whose record says `done`
- **WHEN** a `Notification` of type `permission_prompt` arrives for it, with status `needs`
- **THEN** the record says `needs`

### Requirement: The list answers the arrows

The popover SHALL be navigable from the keyboard without the mouse: ↓ in the
filter field selects the first session still shown and gives the rows the
keyboard; ↓ and ↑ then move the selection between sessions, skipping the group
headers and the footer; and ⏎ opens the selected session, doing what a click on
its row does.

↑ from the first session SHALL return the keyboard to the filter field with the
caret at the end of what was typed, so narrowing and choosing are one movement
in each direction. Escape SHALL put the popover away, from the rows as from the
field.

The selected row SHALL be drawn in the palette's selection colour, and a row
under the pointer in the hover tint, so which row ⏎ will act on is never a
guess and the two questions are told apart. The selection SHALL be scrolled
into view, and SHALL be kept by the session's id across a reload — falling back
to the first row when that session has gone.

#### Scenario: Down out of the field

- **GIVEN** the popover open with the keyboard in the filter
- **WHEN** ↓ is pressed
- **THEN** the first session is selected, drawn as selected, and the rows have the keyboard

#### Scenario: Through the rows and into a session

- **GIVEN** a list of three sessions with the first selected
- **WHEN** ↓ is pressed twice and ⏎ once
- **THEN** the third session is opened, as clicking its row would

#### Scenario: The arrows skip what is not a session

- **GIVEN** two projects of one session each, so a header sits between the rows
- **WHEN** ↓ is pressed from the first session
- **THEN** the second session is selected, not the header

#### Scenario: Back up to the filter

- **GIVEN** the first session selected and `scr` in the filter
- **WHEN** ↑ is pressed
- **THEN** the filter has the keyboard, still reads `scr`, and the caret is at its end

#### Scenario: A reload under the selection

- **GIVEN** a selected session
- **WHEN** an event arrives and the list is rebuilt
- **THEN** the same session is still selected

### Requirement: The register counts a session's subagents

The register SHALL keep, per running session, how many subagents it has out:
raised by a `PreToolUse` whose tool is the one that spawns a subagent, lowered
by a `SubagentStop`, never below nought, and set to nought when a turn ends.

The reset is what keeps it honest. A `SubagentStop` can go missing — the app was
not running, the subagent was killed — and a count that only rose would be
wrong for the life of the session. A finished turn has no subagents running,
whatever was missed in it.

The tool's name SHALL be read from the event the hook was given rather than
assumed. Where the name does not match, the count SHALL stay at nought, so a
guess that is wrong reads as a session with no subagents rather than as a wrong
number.

#### Scenario: two sent off and one back

- **GIVEN** a working session
- **WHEN** it sends two `PreToolUse` events for the spawning tool and then one `SubagentStop`
- **THEN** the register says it has one subagent out

#### Scenario: a turn that ends

- **GIVEN** a session with two subagents out
- **WHEN** its turn ends
- **THEN** the register says it has none

#### Scenario: more back than went out

- **GIVEN** a session with no subagents out
- **WHEN** a `SubagentStop` arrives
- **THEN** the count is nought and not below it

#### Scenario: an ordinary tool use

- **GIVEN** a working session
- **WHEN** it sends a `PreToolUse` for reading a file
- **THEN** the count is nought

### Requirement: A row says how many subagents are out

A row in the popover SHALL say how many subagents its session has out when it
has any — beside what the session last said, in the same dimmed trailing text —
and SHALL say nothing about them when it has none, because a count of nought is
not news.

#### Scenario: a session with subagents

- **GIVEN** a session with two subagents out
- **THEN** its row reads `2 subagents` after its last line

#### Scenario: a session working alone

- **GIVEN** a working session with no subagents
- **THEN** its row says nothing about subagents

### Requirement: A key opens the list of running sessions

The application SHALL offer the list of running Claude sessions on a keyboard
shortcut of ⇧⌘A, from a menu item in the Agent menu, whether or not the
terminal panel that carries the sessions pill is open.

#### Scenario: The key opens the list with the panel closed

- **WHEN** the terminal panel is closed and ⇧⌘A is pressed
- **THEN** the list of running sessions opens
- **AND** it opens whether or not any session is running, so that the answer
  "nothing is running" is one somebody can ask for
- **AND** with nothing running the foot says so and says nothing else, since
  the note about what a click copies has no row to be about

#### Scenario: The list opens over the window that answered the key

- **WHEN** the list is opened by the key
- **THEN** it appears centred horizontally on the window whose menu answered
  the key, near its top edge
- **AND** it is a child of that window, so it follows it and stays above it

#### Scenario: The key and the pill open the same list

- **WHEN** the list is opened by the key rather than by the pill
- **THEN** the filter field, the rows, the arrow keys, ⏎ and Escape behave as
  they do in the popover
- **AND** choosing a row does what choosing it in the popover does

#### Scenario: One list at a time

- **WHEN** the list is open by one route and is opened by the other
- **THEN** the first is put away, so the list is never on screen twice

#### Scenario: Escape and a click elsewhere put it away

- **WHEN** the list opened by the key has the keyboard and Escape is pressed
- **THEN** it closes and the keyboard returns to the window
- **WHEN** another window is clicked while it is open
- **THEN** it closes

### Requirement: The popover says which key opens the list

The popover MUST show the shortcut that opens the list, dimmed, at the trailing
edge of its filter row, so that somebody who reached the list by clicking the
pill can see the key that reaches it next time.

#### Scenario: The shortcut is drawn beside the filter

- **WHEN** the popover is open
- **THEN** `⇧⌘A` is shown at the trailing edge of the row holding the filter
  field
- **AND** it is drawn in the dimmed colour used for text that is not the
  content, so it does not compete with the sessions

#### Scenario: The palette does not repeat the key

- **WHEN** the list was opened by the key
- **THEN** the shortcut is not shown, because it has just been used

