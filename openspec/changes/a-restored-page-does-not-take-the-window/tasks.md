## 1. Tell the two apart

- [x] 1.1 `showLogPage`, `showCommitPage`, `showStashPage` and `showEstatePage`
  take `asked: Bool = true` and only call `leaveTerminalFullScreen()` when it
  is true.
- [x] 1.2 `reopen(page:)` passes `asked: false`, including through the stash's
  own `Task`.

## 2. Checked

- [x] 2.1 **Not the reported sequence, because a driven run cannot have it.**
  `SessionStore.read` refuses a driven run — a run shows what it was given and
  nothing else, which is half of item 0522 — so no project switch inside a run
  restores anything. `--restore-pages log,commit` hands the app's own restore
  path the pages instead: with the panel maximised at 5 s, it reports
  `maximized before=true`, `maximized after=true` and `tabs=[Log, Commit]`.
- [x] 2.2 The same page asked for: `--panel-maximize 2 --log-page` and the
  panel reads `panelMaximized=no` afterwards, as it did before this change.
- [ ] 2.3 `make test` and `make warnings`, both clean by their exit codes.
