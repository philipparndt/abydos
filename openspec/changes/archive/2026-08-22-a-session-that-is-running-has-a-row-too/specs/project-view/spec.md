## MODIFIED Requirements

### Requirement: What a past session left behind has a root of its own

The project view SHALL show, as a root of its own, the Claude Code sessions of
this project: what past ones left behind, and any that is running now.

Every session gets a scratch directory of its own, keyed by the project's path:
reproductions, driven-run logs, screenshots of a fault, a throwaway checkout
somebody was told not to drive against a real one. They are useful for weeks and
reachable only by knowing the shape of the path and a session's UUID.

**A session SHALL have a row when it left files, or when it is active now.**
Keying on files alone hides the session somebody is sitting in: Claude Code makes
the scratch directory when a session starts and writes into it only when a tool
needs a temporary file, so a session that has been asked one question has an
empty directory — seven of the eleven session directories on this machine hold
nothing at all. Keying on the transcript instead SHALL NOT be done: this project
has fourteen transcripts and two scratch directories, and the twelve whose files
went with a reboot would be rows leading nowhere.

**A root rather than a shelf inside `Dependencies`.** What a session left behind
is not something the project depends on, and the heading would be a stretch.
The argument that was made *against* a third root — that it would have to exist
before anything had been found to put in it, which is a permanent empty row on
every project — does not apply: whether a session has left anything is knowable
before anybody asks, because the directory either exists or it does not. So this
root SHALL follow the rule `Dependencies` follows, and be absent when it is
empty.

It SHALL be named for the tool whose files these are. The two shorter names are
taken by other features of this app: "Scratch" is the pane for files somebody
writes on purpose, and "Sessions" is the editor's tabs and splits coming back.

**Nothing SHALL be written, and nothing run.** These are another program's
directories, read the way a lock file is read.

The sessions SHALL be those of the project the window is showing. A worktree is
a project of its own with sessions of its own, and a session started in a
subdirectory is filed under a key of its own and is not this project's.

#### Scenario: a project agents have worked on

- **GIVEN** a project with scratch directories from four past sessions
- **WHEN** the project is opened
- **THEN** the tree has a `Claude Sessions` root under `Dependencies`
- **AND** it holds one row per session, most recent first

#### Scenario: a project nobody has worked on

- **GIVEN** a project with no session directories and nothing running
- **WHEN** the project is opened
- **THEN** there is no `Claude Sessions` root, rather than an empty one

#### Scenario: another project's sessions

- **GIVEN** two projects, each with sessions of its own
- **WHEN** each is opened
- **THEN** each shows only its own

#### Scenario: a session whose files went with a reboot

- **GIVEN** a session whose transcript is still on disk and whose scratch
  directory is not, and which is not running
- **WHEN** the tree is read
- **THEN** that session has no row, rather than a row leading nowhere

## ADDED Requirements

### Requirement: A session that is running has a row before it has written anything

A session running in this project SHALL have a row, whether or not it has written
a file.

This is the case that was reported: a terminal opened in an empty project,
`claude` started in it, and nothing under `Claude Sessions` — because the row was
keyed on a scratch directory that was empty and stayed empty, while the session's
transcript was three hundred kilobytes and growing.

**Where liveness is read from SHALL be the hook while the app is running.**
Claude Code runs a hook on every event and it already posts `event`, `session`
and `cwd` to every listening process; `SessionStart` and `SessionEnd` bracket a
session exactly, so nothing has to be inferred and no directory has to be
watched. A hook event belongs to this project when the slug of its `cwd` is one
of this project's slugs — the same key the scratch directories are filed under.

**Where there was no hook event to hear, liveness MAY be read from when the
session's transcript was last written**, which is the one file written the moment
a session starts and again every few seconds while it runs. This is a proxy and
the row SHALL NOT overstate it: a session the hook has spoken for is *running*,
and a session known only by a recent transcript is *active* and says when it last
wrote.

**A row SHALL NOT claim a size it has not measured.** A session with nothing
under it yet says that it is running, never "0 files", and SHALL NOT be given a
disclosure triangle until there is something behind it.

#### Scenario: a session started in an empty project

- **GIVEN** a project with no session files at all
- **WHEN** a Claude Code session is started in it
- **THEN** the `Claude Sessions` root appears with a row for that session
- **AND** the row says what was asked of it and that it is running, and offers
  nothing to expand

#### Scenario: a live session that starts writing

- **GIVEN** a row for a running session with nothing under it
- **WHEN** that session writes a file into its scratchpad
- **THEN** the row gains what it holds and becomes expandable
- **AND** whatever was expanded and selected in the tree is still expanded and
  selected

#### Scenario: a session running before the window opened

- **GIVEN** a session running in this project, started before the project was
  opened, that has written no files
- **WHEN** the project is opened
- **THEN** it has a row, named by what was asked of it and when it last wrote

#### Scenario: a session that ended without writing anything

- **GIVEN** a row for a running session that has written no files
- **WHEN** that session ends
- **THEN** its row goes, because there is nothing left for it to lead to

### Requirement: The root is read again without the project being reopened

The `Claude Sessions` root SHALL be read again while the project stays open.

It is read once today, when the project is loaded, so a session that starts,
works and ends while somebody watches changes nothing on screen and there is no
gesture short of closing the project that would.

It SHALL be re-read on the events that can change which sessions have a row —
a session starting, a session ending, a turn finishing — and when the window
comes forward, which catches a session that started while the app was asleep or
whose hooks are not installed.

**It SHALL NOT be re-read on every hook event.** A session at work sends one on
every tool use, dozens a minute, and counting what is under a session means
walking it. **`/tmp/claude-<uid>` SHALL NOT be watched**, for the reason already
recorded: every agent on the machine writes there several times a second, and a
watcher would rebuild a root nobody is looking at for somebody else's session.

**A redraw SHALL happen only when the answer changed.** Rebuilding the root
throws away every row's identity and collapses what somebody had open while they
were reading it, and a session that is merely still running has not changed
anything.

#### Scenario: a session started while the project is open

- **GIVEN** an open project showing no `Claude Sessions` root
- **WHEN** a session is started in that project
- **THEN** the root appears without the project being reopened

#### Scenario: a session at work

- **GIVEN** an open project with a running session using tools
- **WHEN** its hook fires on every tool use
- **THEN** the root is not rebuilt for events that change no row

#### Scenario: a session started while the app was asleep

- **GIVEN** a session started in this project while the window was not in front
- **WHEN** the window comes forward
- **THEN** the root has been read again and the session has a row

### Requirement: A driven run reads the root without liveness

A driven run SHALL read the `Claude Sessions` root from files alone, and SHALL
NOT show a session as running or active.

This is the answer already given for the toast corner, asked again about the
tree. A screenshot is pinned to a fixed window size, a fixed panel height and a
fresh copy of the project, because anything that varies per machine is a picture
that looks different for everybody who takes it — and a Claude session running in
somebody else's terminal is exactly that. A tree is pointed at by `--screenshot`
far more often than the corner is.

Both sources of news from outside the run SHALL be declined, not only the hook:
a run that ignores the notification but still reads transcript times has moved
the problem rather than answered it.

**But a way to look at the row SHALL remain**, which is the other half of what
0451 decided. "No toasts on a capture run" was rejected there because
`--toast --screenshot` is the only way to look at a toast, and a corner
photographed empty looks exactly like a corner with nothing to say — a tree
photographed without a live row looks exactly like a tree that cannot draw one.
So a driven run SHALL be able to say that a session is running in the project it
opened, and to say it either at the moment the project opens or after a delay,
because those are two different claims: one is the read on the open path and the
other is the redraw, and the redraw can be driven no other way.

#### Scenario: a capture taken while somebody is working

- **GIVEN** a session running in the project being captured, which the run did
  not name
- **WHEN** a driven run reads the tree
- **THEN** the root shows only what sessions left behind, and no row says
  anything is running

#### Scenario: a picture of a live row

- **GIVEN** a driven run told that a session is running in the project it opens
- **WHEN** the tree is read
- **THEN** that session has a row saying it is running, and the picture is the
  same on every machine
