## 1. The name and the place

- [x] 1.1 `ABYDOS_TERMINAL=<identity>` in every shell the panel starts: a launch environment on `TerminalView`, an `environment` on `PseudoTerminal.startLoginShell`, set where the panel makes a terminal session.
- [x] 1.2 The hook sends `pane` with a tmux place and `terminal` when there is none; `RunningSessions.Session` keeps both, with tests against the payload shape.
- [x] 1.3 `TmuxMirror.select(pane:)`.

## 2. The reach

- [x] 2.1 `BottomPanel.reach(of:)` and `reveal(_:)`: a tab here, a tab in another window, a tmux place — same session, another session, no `tmux` tab yet — or elsewhere.
- [x] 2.2 `AppDelegate` hands the presenter the app's tab identities and a reveal across windows.
- [x] 2.3 The row acts on `reveal`, and copies the resume command only for *elsewhere*.

## 3. The list

- [x] 3.1 One-line rows, the *elsewhere* mark, the dim ink for an unreachable row.
- [x] 3.2 A filter field above the rows, first responder on open, narrowing by project, window name and line, ⏎ choosing the first shown.
- [x] 3.3 A scroll view around the rows and a bounded popover height.

## 4. Proving it

- [x] 4.1 The popover report says each row's reach; `--running-sessions-filter <text>` types into the field in a driven run.
- [x] 4.2 Driven: a session named for a `Local` tab is reported *here* and clicking its row brings that tab in front while `tmux` was; a session with no place is reported *elsewhere*.
- [x] 4.3 Driven: a filter narrows the rows and the report shows only the matches.

## 5. Finishing

- [x] 5.1 Say it in the release notes.
- [x] 5.2 `make test` and `make warnings`, both clean, both by their exit codes. Green here on 2026-09-03: 4005 tests in 511 suites, exit 0, load 18.8 over 14 cores; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the deltas in this change are
what it makes true.
