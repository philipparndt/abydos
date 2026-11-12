## Why

A user with several monitors, 2026-10-22: one Abydos window per monitor, an
agent working in one and something else going on in the other — the way
IntelliJ opens each project in a window of its own. What they got instead:

- **File ▸ New Window opened a copy of the window in front.** `newWindow` in
  `AppDelegate.swift` loads the front window's project on purpose — "a second
  window is nearly always wanted for the work already in progress" — and
  nothing about the result says it is the same project twice.
- **The terminals in the two windows dragged each other about.** Both panels
  ran `tmux new -A -s <project>` (`TmuxMirror.attachArguments`), so both were
  clients of one tmux session. A session has one current window: clicking a tab
  in one Abydos window switched the other, a `+` in one jumped both to the new
  window, and tmux sized the shared window to fit both clients.

There is no backlog item; this came from an exploration of the report, with two
simulations of the behaviour the exploration compared.

Reading the code found a third way to the same state that nobody had reported:
**following the terminal** (`MainWindowController.follow(reported:)`) switches
the window to whichever project the shell walked into, without asking whether
another window already has it open — and switching tmux session with `C-b s`
counts as walking. The project switcher, the recent list and the worktree menu
are guarded already: `open(projectAt:)` raises the window that has the project.

## What changes

- **A project is open in at most one window.** Every way into a project raises
  the window that has it, and that rule wins over every other one here. Torn-off
  windows, which hold one file and not a project, are outside it as they are
  now.
- **Following the terminal into a project another window has** leaves this
  window where it is and says so, with a way to go there.
- **File ▸ New Window opens a picker** of projects and of the tmux sessions
  running on the server — how many windows each has, whether an agent is at
  work in it, which Abydos window is on it. A project opens as now. A session
  opens on the folder it was started in (`#{session_path}`), unless that project
  is open elsewhere, when the project rule raises that window instead.
- **A terminal that arrives at a tmux session another window is on gets a
  grouped session of its own** — `tmux new -t <base> -s <name>` — which shares
  the session's windows and keeps its own current window. Both Abydos windows
  can look at any tmux window without moving the other. The grouped session
  removes itself when its last client goes (`destroy-unattached`), carries the
  status-bar option the base session has, and is never what a project remembers.
- **Choosing the tmux window the other Abydos window is showing** — by its tab,
  or with tmux's own keys (`C-b w`, `C-b n`, `C-b 1`) — raises that window, and
  this one stays on, or goes back to, what it showed. A window joining a group
  starts on a tmux window the other is not showing.
- **A running agent is counted once**, however many sessions show its window:
  seeded records are keyed by tmux's `#{window_id}` rather than by session and
  index.

## Not in this change

- Two windows on one project on purpose. Nobody has a use for it yet, and it
  would need a rule for which window writes the project's session file.
- Sessions named by folder alone: `~/work/api` and `~/oss/api` still share
  `api`. The picker makes it visible; fixing the name is its own change.

## Capabilities

### New Capabilities

- `project-windows`: which window a project is in, how a new window is opened,
  and how two windows share the tmux server without moving each other.

### Modified Capabilities

- `running-sessions`: a tmux window shown by several sessions is one record.

## Impact

- `AppDelegate.swift` — `newWindow`, `open(projectAt:from:)`.
- `MainWindowController+Terminal.swift` — `follow(reported:)`.
- `MainWindowController+Loading.swift` — `sessionToAttach`.
- `TmuxMirror.swift` — attaching, grouped sessions, status-bar option.
- `BottomPanel+Tmux.swift`, `BottomPanel+Terminals.swift` — the tab strip and
  the session menu.
- `RunningSessions.swift` — the seeded key.
- A new picker window in `Sources/AbydosApp/Titlebar` or beside it.
