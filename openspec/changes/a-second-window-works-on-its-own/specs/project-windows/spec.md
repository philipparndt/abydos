# Project windows

## ADDED Requirements

### Requirement: A project is open in one window at most

Abydos SHALL show a project in at most one window. Every way of reaching a
project — the switcher, the recent list, the worktree menu, File ▸ New Window,
the Finder's *New Terminal Here*, a file or folder handed over by the system,
and following the terminal — SHALL raise the window that already has it.

This rule SHALL win wherever it meets another rule in this capability.

#### Scenario: the switcher asked for a project open elsewhere

- **GIVEN** window 1 on `abydos` and window 2 on `website`
- **WHEN** `abydos` is chosen from window 2's switcher
- **THEN** window 1 is raised and window 2 stays on `website`

### Requirement: A torn-off window is not a project window

A torn-off window holds one file and is not a project window. It SHALL neither
count as having the project nor be the window raised for it.

#### Scenario: a torn-off window does not count

- **GIVEN** window 1 on `abydos` and a torn-off window holding one of its files
- **WHEN** `abydos` is chosen anywhere
- **THEN** window 1 is raised, not the torn-off window

### Requirement: Following the terminal stops at a project another window has

A window that follows its terminal SHALL NOT switch to a project another window
has open. It SHALL stay on its own project and say, where the terminal is, that
the project is open in the other window, with a control that raises it.

The terminal is left where the shell put it: the shell's directory is somebody's
and nothing is typed into it.

#### Scenario: a shell walks into a project open elsewhere

- **GIVEN** window 1 on `abydos`, window 2 on `website` following its terminal
- **WHEN** window 2's shell runs `cd ~/dev/abydos`
- **THEN** window 2 is still on `website`, and says `abydos` is open in window 1

#### Scenario: a tmux session switch counts as a walk

- **GIVEN** the same windows, window 2's terminal in tmux
- **WHEN** window 2's client is switched with `C-b s` to a session whose pane is
  in `~/dev/abydos`
- **THEN** window 2 is still on `website`, and says the same

### Requirement: A new window asks what to open

File ▸ New Window SHALL open a picker of projects and of the sessions on the
tmux server, rather than a copy of the window in front. Choosing a project SHALL
open it as the switcher would. Dismissing the picker SHALL open nothing.

#### Scenario: a project nobody has open

- **GIVEN** window 1 on `abydos`
- **WHEN** File ▸ New Window is chosen and `website` picked
- **THEN** a second window opens on `website`

#### Scenario: the picker dismissed

- **WHEN** File ▸ New Window is chosen and the picker dismissed
- **THEN** no window opens

### Requirement: The picker says what each project and session holds

The picker SHALL say of each project whether a window has it and whether it has
a tmux session yet, and of each session how many windows it has, whether an
agent in it is working or waiting, and which window is attached to it. A session
and those grouped with it SHALL be one row.

#### Scenario: a session with an agent at work

- **GIVEN** session `AbydosDev` with three windows, `Claude` badged `working`,
  and window 1 attached
- **WHEN** the picker opens
- **THEN** its row says three windows, one agent working, and window 1

### Requirement: A session chosen opens the folder it was started in

Choosing a session SHALL open a window on the folder the session was started
in, its `session_path`, with the terminal attached to that session — unless that
folder's project is open in a window already, when that window SHALL be raised
and nothing opened.

#### Scenario: a session started outside Abydos

- **GIVEN** a detached tmux session `Presentation` started in `~/talks/tmux`
- **WHEN** it is chosen in the picker
- **THEN** a window opens on `~/talks/tmux` and its terminal is attached to
  `Presentation`

#### Scenario: a session whose project is open

- **GIVEN** window 1 on `abydos`, attached to tmux session `abydos`
- **WHEN** session `abydos` is chosen in the picker
- **THEN** window 1 is raised and no window is opened

### Requirement: Two windows on one tmux session do not move each other

When a window's terminal is about to be attached to — or has been switched to — a
tmux session another window's terminal is on, Abydos SHALL give it a session of
its own in the same group instead (`tmux new -t <base> -s <name>`). Each SHALL
keep its own current window while sharing the list of tmux windows.

#### Scenario: a second window looks at a different tmux window

- **GIVEN** window 1's terminal on session `AbydosDev`, showing `Claude`
- **WHEN** window 2's client is switched to `AbydosDev` and then shows `Tests`
- **THEN** window 1 still shows `Claude`

#### Scenario: a window made in one is a tab in both

- **GIVEN** windows 1 and 2 on `AbydosDev` and its grouped session
- **WHEN** a tmux window is made from window 2
- **THEN** it is a tab in both, and window 1's current window has not changed

### Requirement: A grouped session goes with the window that made it

A grouped session SHALL be set to remove itself when its last client detaches
(`destroy-unattached`), so that it ends with its window even when the app does
not end cleanly. A window that leaves a grouped session for another SHALL leave
nothing behind.

#### Scenario: the window is closed

- **GIVEN** window 2 on a grouped session of `AbydosDev`
- **WHEN** window 2 is closed
- **THEN** the grouped session is gone from the server and every tmux window it
  showed is still in `AbydosDev`

#### Scenario: the window moves on

- **GIVEN** window 2 on a grouped session of `AbydosDev`
- **WHEN** window 2's client is switched to `Usermanual`
- **THEN** the grouped session is gone from the server

### Requirement: A grouped session stands in for its base and is not remembered

A grouped session SHALL carry the status-bar option its base session has. It
SHALL NOT be the session a project remembers: the project remembers its base.

#### Scenario: the status bar is hidden

- **GIVEN** tmux's status bar hidden for `AbydosDev`
- **WHEN** window 2 is given a grouped session of it
- **THEN** window 2's terminal shows no status bar either

#### Scenario: the project is reopened

- **GIVEN** window 2 on `abydos`, closed while on a grouped session of `abydos`
- **WHEN** `abydos` is opened again with no other window on it
- **THEN** its terminal attaches to `abydos` itself

### Requirement: A terminal in another program counts as another window

A tmux session SHALL count as taken when any other client is attached to it —
another copy of Abydos, a terminal in another program — not only another of
this app's windows, and a window's terminal arriving there SHALL get a grouped
session as it would beside one of this app's windows. A client in another
program that a `C-b w` from here moved SHALL be put back to the window it had in
front.

#### Scenario: another copy of Abydos is on the session

- **GIVEN** a terminal in another program attached to `AbydosDev`, showing
  `Tests`
- **WHEN** a window opens on the project with its terminal on `AbydosDev`
- **THEN** its terminal is on a grouped session of its own, and the other
  terminal still shows `Tests`

#### Scenario: a C-b w through the other program's session

- **GIVEN** the same, and a second window on `website`
- **WHEN** `AbydosDev`'s `Infra` is chosen with `C-b w` in the second window
- **THEN** the second window is on a grouped session showing `Infra`, and the
  other terminal shows `Tests`

### Requirement: Attaching finds the session's group

When a project's terminal attaches to its session and the base session is gone
but a session grouped with it is not, Abydos SHALL join that group rather than
make a new, empty session under the base name.

#### Scenario: the base session was killed

- **GIVEN** `AbydosDev` killed while its grouped session still holds `Claude`
- **WHEN** a window opens on the project and its terminal attaches
- **THEN** its tabs show `Claude`

### Requirement: A tab already in front elsewhere raises that window

Choosing, on the panel's tab strip, the tmux window another Abydos window is
showing SHALL raise that window and leave this one where it was.

#### Scenario: a click on the agent's tab

- **GIVEN** window 1 showing tmux window `Claude`, window 2 on the same group
- **WHEN** `Claude` is clicked on window 2's strip
- **THEN** window 1 is raised, and window 2 still shows what it showed

### Requirement: tmux's own keys onto a window in front elsewhere raise that window

When tmux's own keys — `C-b w`, `C-b n`, `C-b 1` — bring to a window's terminal
the tmux window another Abydos window has in front, Abydos SHALL raise that
window and take this one back to the tmux window, and session, it showed
before. Two Abydos windows SHALL NOT be left showing one tmux window, which tmux
sizes for one of them only.

#### Scenario: the second window chooses the first window's tmux window

- **GIVEN** window 1 showing `Tests` of `AbydosDev`, window 2 on `AbydosDev~2`
  showing `Claude`
- **WHEN** `Tests` is chosen with `C-b w` in window 2
- **THEN** window 1 is raised, window 2 shows `Claude` again, and window 1 still
  shows `Tests`

### Requirement: Entering a session lands beside the other window's tmux window

A terminal arriving from another session — `C-b s`, the session menu, or a
`C-b w` into another session — lands on that session's current window, which
nobody chose; tmux cannot tell the two apart. Arriving so on the window another
Abydos window has in front, it SHALL move to a window of the session nobody has
in front, raising nothing; only with none left SHALL it raise that window and go
back.

#### Scenario: entering the session from another one

- **GIVEN** window 1 showing `Tests` of `AbydosDev`, window 2 on `website`
- **WHEN** `AbydosDev` is chosen with `C-b s` in window 2
- **THEN** window 2 is on `AbydosDev~2` showing a window that is not `Tests`,
  and window 1 is not raised and still shows `Tests`

#### Scenario: entering it with nothing beside

- **GIVEN** window 1 showing `Tests`, the only window of `AbydosDev`, and window
  2 on `website`
- **WHEN** `AbydosDev` is chosen with `C-b s` in window 2
- **THEN** window 1 is raised, window 2 is back on `website`, and no grouped
  session is left behind

### Requirement: A window whose tmux window closes does not land on another's

When the tmux window a window's terminal shows is closed, and tmux puts the
terminal on the tmux window another Abydos window has in front, Abydos SHALL
raise nothing and move the terminal to a window of the session that no other
Abydos window, and no terminal in another program, has in front. With none left
the terminal SHALL leave tmux, as tmux leaves a session whose last window
closed, and say why. Abydos SHALL NOT make a window or switch session for it.

#### Scenario: a free window is left

- **GIVEN** window 1 showing `Claude` of `AbydosDev`, window 2 showing `Tests`
  on a grouped session, and `Infra` shown by nobody
- **WHEN** `Tests` is closed
- **THEN** window 2 shows `Infra`, window 1 still shows `Claude`, and neither is
  raised

#### Scenario: nothing free is left

- **GIVEN** the same without `Infra`
- **WHEN** `Tests` is closed
- **THEN** window 2's terminal has left tmux and says `Claude` is in front in
  another window, and window 1 still shows `Claude`

### Requirement: A window that steps away goes back even when its session has gone

A window that steps away from a tmux window another Abydos window has in front
SHALL go back to the tmux window it showed before, even when the grouped session
it showed it in has removed itself, or another client is on that session: then
through a grouped session of its own in that session's group.

#### Scenario: it came from a grouped session of its own

- **GIVEN** a terminal in another program on `AbydosDev`, window 1 on a grouped
  session of `AbydosDev` showing `Tests`, window 2 showing `Usermanual`'s `Docs`,
  its only window
- **WHEN** `Docs` is chosen with `C-b w` in window 1
- **THEN** window 2 is raised, window 1 shows `Tests` of `AbydosDev` again on a
  grouped session, and the other terminal still shows what it showed

### Requirement: A window joining a group starts beside the other

A window's terminal that joins a group SHALL start on a tmux window no other
Abydos window, and no terminal in another program, has in front, when the group
has one. It SHALL NOT move another window's terminal to get there.

#### Scenario: the group's first window is the other's

- **GIVEN** window 1 showing `Claude`, the first window of `AbydosDev`
- **WHEN** window 2 opens with its terminal on `AbydosDev`
- **THEN** window 2 shows another window of `AbydosDev`, and window 1 still shows
  `Claude`
