## 1. Seeing the fault

- [x] 1.1 `--zoom-gesture click-status`, `click-clear` and `click-x<n>` in the
      instrument, reporting the view under the point and the responder chain
      above it; `LaunchOptions.swift` names them.
- [x] 1.2 Built under a throwaway identifier and run against a scratch
      repository: the click lands on `RunControl` and the frame does not move.
      Recorded in the design under *What was measured*.

## 2. Finding what zooms

- [x] 2.1 Forwarding from `mouseDown`, then the release and drags too, then
      `mouseDownCanMoveWindow`: each built, traced where it could be, tested
      by hand by the reporter, and withdrawn. The trace table is in the design.
- [x] 2.2 Two builds side by side under `de.rnd7.abydos.zoomA` and `zoomB`:
      A with the run control shrunk, B with the room kept and everything
      forwarded. A zooms, B does not. Recorded.

## 3. The fix

- [x] 3.1 `RunControl` loses the status drawing, its reserved width and the
      cross; keeps the words; `onStatusChanged` tells the title bar.
- [x] 3.2 `TitlebarStatus`, new, on the backdrop: draws the message and the
      cross, hit-tests only the cross, hover and tip from a tracking area.
- [x] 3.3 `TitlebarController` owns it, places it left of the run control on
      status changes, strip re-layout and inset changes, and hides it with no
      message, no room or the run control in the overflow menu.
- [x] 3.4 Wiring in `MainWindowController`, `+Sessions`; the `run:status` and
      `run:clear` hovers in `+Driving2` follow the message.
- [x] 3.5 Driven: `click-status` lands on the flexible space with and without a
      message; the message survives a posted double-click; `click-clear`
      clears it with the frame unchanged; a screenshot shows the placement.
- [x] 3.6 By hand, the reporter, on the structural build: the room right of the
      well zooms, repeatedly, and the message zooms and stays. Confirmed
      2026-09-16.

## 4. The narrow window

- [x] 4.1 The flexible space kept at the run control's priority — and found
      collapsed anyway while the toolbar overflowed.
- [x] 4.2 `PillButton.hasContent`, `isCollapsedForRoom`, `shownSize`,
      `naturalWidth`; `TitlebarCapsule.roomWidth`, `isCollapsedForRoom`,
      `minimumOuterWidth`; `TitlebarController.fitStrip` on inset, re-layout
      and every setter.
- [x] 4.3 Driven at 800, 1000, 1280 and 1600 wide: nothing put away, the run
      control trailing, flexible space under the free strip; screenshot at
      800×600.
- [x] 4.4 By hand, the reporter: a narrow window zooms from the strip beside
      the run control. Confirmed 2026-09-16.

## 5. Before finishing

- [x] 5.1 `docs/release-notes-0.21.2.md`: one `##`.
- [x] 5.2 `make test` and `make warnings`, both clean, by their exit codes;
      `npx openspec validate the-run-control-lets-the-title-bar-gesture-through`.
      2026-09-16, Xcode 26.6 toolchain, on the final code: `make warnings`
      exit 0, no warnings; `make test` exit 0, 4492 tests in 572 suites, load
      6.0 to 12.1 over 14 cores. An earlier full run exited 2 under load 21
      because `receivesDiagnosticsForAFileThatDoesNotParse` waited 75 s on a
      language server; alone it passes in 4 s, and every full run since was
      green.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `window-frame` is what this
change amends.
