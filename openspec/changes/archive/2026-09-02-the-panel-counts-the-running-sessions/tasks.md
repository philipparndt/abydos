## 1. The register, in AbydosKit

- [x] 1.1 Give `RunningSessions` a per-session record — status, tmux session and window, last announced line and message, time of the last event — in place of the bare set of ids per slug, keeping `ids(forSlugs:)` and `belongs` as they are.
- [x] 1.2 Make `note` return the slug when a status changes as well as when a session appears, ends or finishes a turn, and still nil for a tool-use event from a session whose status it already had; keep `aToolUseFromAKnownSessionAsksForNothing` green.
- [x] 1.3 Add the queries the pill and popover ask: counts of working and needing input against a clock and `TmuxMirror.Window.staleAfter`, and sessions grouped by slug with the given slugs first and the rest most recent first.
- [x] 1.4 Let the mirror seed a record from a window's `@ai_status` when the register has none for it, and let the hook's own record replace it at the next event.
- [x] 1.6 Carry `pane_current_path` on `TmuxMirror.Window` and file a seeded record under it, so a window in another project is grouped under that project.
- [x] 1.5 Pick the bound after which a hollow record is dropped, name the reason in a comment, and pin it in `RunningSessionsTests` beside a test for each scenario in the spec.

## 2. The pill, on the strip

- [x] 2.1 Draw the pill in `PanelTabStrip`'s trailing controls, left of the tmux tag, with the shared drawn-control library so it scales; two dots with digits, dots only under the tag's own narrowing width, and no frame at all when the register is empty.
- [x] 2.2 Redraw the pill from `ClaudeWatch.sessionsChanged` in every window, and run the one-second staleness timer only while a working record exists, in the shape of `syncSpinner`.
- [x] 2.3 Add a click callback beside `onMirrorTagClicked` handing the pill's frame to the panel.

## 3. The popover

- [x] 3.1 Build the popover from the register's grouped query: group titles from the `cwd`'s last component and home-relative parent, rows with badge, window name and index or last line, the line and message beneath, and the age.
- [x] 3.2 Reveal the tmux window for a row in the mirrored session through `revealTmuxWindow`; copy `AgentSessions.resumeCommand` and say so with the navigator's toast for any other row.

## 4. Driving and proving it

- [x] 4.1 Extend `--claude-running` to take `:<status>` and to be given more than once, defaulting to `working`; report the pill's counts and the popover's rows through the driver as toasts are.
- [x] 4.2 Driven: two sessions in two states — the pill reads 1 and 1, and the popover has both rows under the run's project.
- [x] 4.3 Driven with a strip full of tabs and a session running: the pill's counts are legible on their own ground and the tab under it is hidden, per the terminal delta.
- [ ] 4.4 Screenshot of the pill and the open popover for the release notes, through `Scripts/screenshots.sh`. The shot is in the script; running it needs the examples checkout, which this machine does not have, so the picture was taken by hand against a scratch project instead and the script is untested here.

## 5. Finishing

- [x] 5.1 Say it in the release notes: the pill, what it counts, what a row does, and that sessions outside the mirrored tmux session appear at their next event.
- [x] 5.2 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `running-sessions` spec and
the `terminal` delta in this change are what it makes true.
