Every tmux this work starts in a test, a driven run or a probe is on a server of
its own (`-L <name>`), and so is every kill. Driven runs use a throwaway bundle
id, an unpinned UUID and a scratch copy of a project — see `CLAUDE.md`.

## 1. One project, one window

- [x] 1.1 `AppDelegate.window(showing:)`: the window on a root, standardised,
      torn-off windows skipped. `open(projectAt:from:)` asks it.
- [x] 1.2 `follow(reported:)` asks it before switching: a project open elsewhere
      leaves the window where it is and puts up "open in window N → Go there".
- [x] 1.3 The Finder service, `application(_:open:)` and `openFromTerminal` reach
      the same question (they go through `open(projectAt:)`; checked, not
      assumed).
- [x] 1.4 Tests for the question itself in AbydosKit if it can live there, and a
      driven run: two windows, a `cd` into the other's project, the window has
      not moved.

## 2. File ▸ New Window

- [x] 2.1 `TmuxMirror.sessionsForPicker`: one `list-sessions` with
      `session_path`, `session_windows`, `session_attached`, `session_group`.
- [x] 2.2 The picker: projects as the switcher lists them, marked open in a
      window or with a session; the server's sessions, a group as one row, with
      agent state and the Abydos window attached.
- [x] 2.3 Choosing a project opens it; choosing a session opens its
      `session_path` and attaches to it; either raises the window that already
      has the project. Dismissing opens nothing.
- [x] 2.4 `newWindow` opens the picker; the comment that defended the copy goes.

## 3. Grouped sessions

- [x] 3.1 `TmuxMirror.groupedAttachArguments(base:name:)`: `new -t`,
      `destroy-unattached on`, `allow-passthrough on`, as one command line.
- [x] 3.2 At attach: the terminal's start command asks which sessions other
      windows' panels are on and joins the group when it is taken (decided in
      `attachCommand` rather than `sessionToAttach`; see design).
- [x] 3.3 After a switch: `refreshTmuxWindows` finds the client on a session
      another window is on, makes the grouped session at the window being shown
      and switches the client to it.
- [x] 3.4 The status-bar wish is applied to grouped sessions as to the base.
- [x] 3.5 The project remembers the base, never the grouped name.
- [x] 3.6 A gone base is found through `session_group`, and the attach joins the
      group.
- [x] 3.7 The session menu and *Close Sessions…* show a group as one row.
- [x] 3.8 Choose the grouped name (design, Open) after seeing it in a real
      `C-b s`, and record the choice in `design.md`.
- [x] 3.9 Tests on a scratch server: two clients, a tab chosen in one does not
      move the other; a window made in one is in both; the grouped session goes
      when its client detaches; a killed base is joined through its group.
      (Decisions in `TmuxGroupsTests`; tmux's side by probes and driven runs on
      a `-f /dev/null` scratch server, not in the suite, which has no tmux.)
- [x] 3.10 `TmuxClientWatch`: the same for panels whose tabs are this app's
      own, which have no poll (found in the driven run; see design).

## 4. The same tmux window in two Abydos windows

- [x] 4.1 A tab click for the window another Abydos window shows raises that
      window, compared by `window_id`.
- [x] 4.2 The same reached through tmux's keys raises that window and takes this
      one back to where it was (reversed after the first test, 2026-10-26; see
      design).
- [x] 4.4 A window joining a group starts on a tmux window nobody else has in
      front.
- [x] 4.5 Any other client on a session — another copy of Abydos, iTerm — takes
      it, and an outside client moved by a `C-b w` from here is put back
      (second test, 2026-10-26; see design).
- [x] 4.3 Tests for the comparison; a driven run of the click.

## 5. Counted once

- [x] 5.1 `TmuxMirror.windows` reads `#{window_id}`.
- [x] 5.2 `RunningSessions` keys seeded records by `window_id` and holds the
      sessions that seeded each; `forgetSeeded` takes one away.
- [x] 5.3 Tests for both scenarios in `running-sessions`, and checked that the
      first fails with the old key.

- [x] 5.4 `Scripts/windows-check.sh` (`make windows`) drives two windows of the
      built app through every tmux case here, plain and mirrored, on a scratch
      server, and was checked to fail on the step-away reported 2026-11-09.

- [x] 5.5 A window whose tmux window closes under it moves to a free one, or
      leaves tmux with a toast; three cases in `make windows`, checked to fail
      before.

## 6. Finishing

- [x] 6.1 `make test` and `make warnings`, both clean, by their exit codes.
- [x] 6.2 Release notes for the next version, in the shape of 0.20.6 — drafted
      in `release-notes.md` here, since the version is the maintainer's to pick.
- [x] 6.3 No `openspec/specs` file is made untrue. On archive the terminal spec's
      "A window follows its terminal out of the project" gains a sentence
      pointing at `project-windows` for the project another window has.
