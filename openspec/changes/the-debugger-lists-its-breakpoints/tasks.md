## 1. Rows, in the kit where they can be tested

- [ ] 1.1 Add `Sources/AbydosKit/Debug/BreakpointRows.swift`: a row value —
      path, line, the name to show, condition, enabled, verified — and one
      function from `[String: [Breakpoint]]` and a project root to rows sorted by
      path and then by line. Naming is its whole job: relative to the root inside
      the project, in full outside it. No view code, per the house rule.
- [ ] 1.2 Add `Tests/AbydosKitTests/BreakpointRowTests.swift`: three files come
      back in path order; two in one file come back in line order; a file under
      the root is named relative to it; a file outside it is named in full; an
      empty set gives no rows. Names are sentences.

## 2. A debug pane that exists without a session

- [ ] 2.1 `DebugPane.session` becomes `DebugSession?`. Every one of the
      forty-nine uses answers "there is nothing" when it is nil — the state the
      pane already draws when a session ends. No force-unwraps: a `!` here is the
      review's one thing to look for.
- [ ] 2.2 `DebugPane.debugSession` becomes optional and `isSessionActive` false
      with no session, so `BottomPanel.activeDebugSession` is nil for an empty
      pane. Read the callers that decide things from it and confirm each is
      right: `DebugCoordinator.currentDebugSession`, `toolStrip.isDebugRunning`,
      `RunCoordinator.debugSession`, `MainWindowController.validateMenuItem`.
      `debuggedProject` must still answer, since it is what scopes the
      breakpoints to a project.
- [ ] 2.3 `BottomPanel.showDebug()` makes the pane when there is none, rooted at
      the panel's working directory and with `Session.projectRoot` set as
      `makeDebugSession` sets it. `MainWindowController.showDebugPanel` opens the
      panel and it.
- [ ] 2.4 Check that starting a session while the empty pane is open leaves one
      debug pane, not two: `makeDebugSession` already closes an existing one.

## 3. The Breakpoints tab

- [ ] 3.1 A segmented control for the left-hand side — Stack | Breakpoints —
      built the way `sideTabs` is and placed in the toolbar row at its leading
      end. `showStack()` and `showBreakpoints()` beside the existing
      `showVariables()` and `showConsole()`. A pane with no session opens on
      Breakpoints; one with a session opens on Stack.
- [ ] 3.2 `BreakpointList`, an `NSView` over an `NSTableView`, drawing the rows
      from 1.1: the marker as the gutter draws it, the name and line, the code,
      and the condition where there is one. A project with none says so in a
      sentence naming the way to make one.
- [ ] 3.3 The code for a row: the editor's document when the file is open, the
      file otherwise, nothing when it is gone. Read for the rows the table asks
      for, cached per file, and the cache dropped when the set changes. Nothing
      is written to the session file.
- [ ] 3.4 Row verbs, each through `DebugCoordinator` so a running session is told
      and the change is written down: open at the line, enable and disable,
      delete, the options sheet, and silence every other one. The row's context
      menu matches the gutter's.
- [ ] 3.5 `DebugCoordinator` gains a hook that says the set changed, fired from
      `publishPendingBreakpoints`, `syncBreakpointsToEditor` and
      `adoptBreakpoints` — the three funnels every change already passes. The
      list rebuilds from it, and holds no copy of its own.

## 4. Where a session is started

- [ ] 4.1 `RunControl.showStartMenu()` gains Debug Executable… and Attach to
      Process…, and Debug Go Package where the project is a Go one. `RunControl`
      gains `onDebugExecutable`, `onAttachToProcess`, `onDebugGoPackage` and the
      `isGoProject` question, beside the hooks it already has.
- [ ] 4.2 Wire the three in `MainWindowController` to `debugExecutable`,
      `attachToProcess` and `goDebug`, which do not move.
- [ ] 4.3 `ToolWindowBar.debugButtonPressed` becomes `onToggleDebug?()` and
      nothing else. Delete `onDebugGoPackage`, `onDebugExecutable`,
      `onAttachToProcess` and `isGoProject` from the strip, and their four
      wirings in `MainWindowController+Layout`. `isDebugRunning` stays: it is
      what colours the button.
- [ ] 4.4 Check the Run menu's own Attach to Process… still validates and still
      works: it is not the rail's and does not move.

## 5. Driving it, and finishing

- [ ] 5.1 A driven-run verb that opens the debug pane with nothing running and
      prints the rows — file, line, enabled, condition — the way
      `inspectDebugStateForTesting` prints a stop. It is the only way to check
      any of section 3 without a person, since `Tests/` covers `AbydosKit` and
      nothing in `AbydosApp`.
- [ ] 5.2 Drive it against a copy under the scratchpad, with a throwaway bundle
      id and an unpinned UUID, and a defaults domain of its own: set breakpoints
      in two files, open the pane with nothing running, and read the rows back.
      Never `make install`.
- [ ] 5.3 `make test` and `make warnings`, both clean, and their exit codes read
      rather than their output skimmed.

## What this makes untrue

`openspec/specs/left-rail/spec.md` describes a rail whose buttons say which pane
is in front, and is silent on the debug button asking how to start a session
instead of opening one. The delta in `specs/left-rail/spec.md` adds the rule that
silence left out; nothing already written there stops being true, and the case it
already specifies — the debug pane in front with no session running — becomes
reachable on purpose rather than only as the leftover of a session that ended.

`openspec/specs/debug-sessions/spec.md` stays true as it stands: a pane with no
session shows the same nothing its first requirement demands of a session that
has ended.

There is no `.abydos/backlog/spec` file to name. That backlog is gone, and
`openspec/specs` is the account it kept.
