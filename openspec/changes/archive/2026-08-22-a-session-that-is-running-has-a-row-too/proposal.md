## Why

**The session somebody is in right now is the one the tree cannot show them.**
Asked this morning: a terminal was opened in an empty project, `claude` was
started in it, and nothing appeared under *Claude Sessions*. That is two
separate faults, and the second survives the first being worked around.

**A row is keyed on files, and a session that has not written one leaves
nothing to key on.** `AgentSessions.read` decides `hasAnything` by asking
whether `scratchpad` or `tasks` holds a non-hidden entry
(`Sources/AbydosKit/Project/AgentSessions.swift:192`); a session that fails it
is dropped before it is ever a row (`:155`), and once the measuring walk lands
`SessionTree.build` drops it again on `fileCount == 0`
(`Sources/AbydosApp/Navigator/SessionTree.swift:121`). Claude Code makes the
scratch directory when a session starts and writes into it only when a tool
needs a temporary file, so a session that has been asked one question has an
empty directory and no row. On this machine, now: this project holds two
session directories and one of them — the session writing this proposal — is
empty, and across the five projects under `/tmp/claude-501` seven of eleven
session directories hold nothing at all. Meanwhile its transcript,
`~/.claude/projects/-Users-philipparndt-dev-abydos/fff7b0f9-….jsonl`, was 336 KB
and being written to every few seconds.

**And the root is read once, at project open.** `refreshSessions()` has exactly
one caller — `load(project:)`, at
`Sources/AbydosApp/Navigator/ProjectNavigatorViewController.swift:269`. Not
`reloadTree()`, not `refreshFromDisk()` when the window comes forward, and not
the filesystem watcher, which watches the project's own directory and
deliberately not `/tmp/claude-<uid>`. So even a session that *does* write a
file appears only when the project is closed and opened again, and nothing in
the app ever says so.

**The signal is already in the building.** The hook posts a distributed
notification on every Claude Code event carrying `event`, `session` and `cwd`
(`ClaudeHookRunner.announce`), and `ClaudeWatch` is already listening to it —
it acts on the events worth a toast and drops the rest, including
`SessionStart` and `SessionEnd`. Liveness does not need polling, a process
table, or a watcher on a directory every agent on the machine writes to.

No originating backlog item: the backlog was dropped on 2026-08-19, and this was
reported on 2026-08-22.

## What Changes

- **A session that is running now has a row, whether or not it has written
  anything.** The rule becomes *left files, or active now* — not *has files*,
  which hides the live one, and not *has a transcript*, which would put
  fourteen rows on this project for two directories that still exist.
- **A live row says so, and says what it can.** It carries what was asked of it
  and that it is running; where there are no files yet it says that rather than
  inventing a size.
- **The root refreshes without the project being reopened**, on a hook event
  whose `cwd` is this project, and again when the window comes forward. A
  session that starts, works and ends while the window is open is seen to do
  all three.
- **A session's own liveness is read from the hook while the app is up**, and
  at project open from when its transcript was last written — the one file that
  is written the moment a session starts and every few seconds after.
- **Still absent when there is nothing to show.** A project with no live session
  and no files kept has no root, exactly as today.
- **Not proposed: a row per transcript.** Twelve of this project's fourteen
  transcripts belong to sessions whose `/tmp` directories went with a reboot,
  and the archived change decided that a row leading nowhere is worse than no
  row. That decision stands.
- **Not proposed: watching `/tmp/claude-<uid>`.** The archived design rejected it
  for a reason that has not changed — every agent on the machine writes there
  several times a second, and a watcher would rebuild a root nobody is looking
  at for somebody else's session.
- **Not proposed: offering to resume a session that is already running.**
  `claude --resume` on a live session is not a thing anybody wants pasted into a
  terminal.

## Capabilities

### New Capabilities

<!-- None. Which sessions get a row, and when the root is re-read, are things
     `project-view` already states. -->

### Modified Capabilities

- `project-view`: *What a past session left behind has a root of its own* is
  keyed on what a session left, and its title says *past*. It gains a session
  that is running, the rule that decides which sessions get a row, and when the
  root is read again after the project was opened.

## Impact

- `Sources/AbydosKit/Project/AgentSessions.swift` — what makes a session worth a
  row, and where liveness is read from. Pure, and testable without a tree.
- `Sources/AbydosApp/Navigator/SessionTree.swift` — the row for a session with
  nothing under it yet, and the subtitle that must not claim a size it has not
  measured.
- `Sources/AbydosApp/Navigator/ProjectNavigatorViewController.swift` —
  `refreshSessions()` gaining callers, and the identity comparison that decides
  whether the redraw happens at all.
- `Sources/AbydosApp/ClaudeWatch.swift` — the events it currently drops become
  worth passing on, without becoming worth a toast.
- No new dependency, no network, nothing run, and nothing written into another
  program's directories.
