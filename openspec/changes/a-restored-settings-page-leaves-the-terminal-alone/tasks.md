## 1. Name it

- [ ] 1.1 Ask the reporter which gesture "switching back" is — ⌘, or the gear,
      a macOS Space, or another window of this app — and write the answer into
      the design. The run below fixes and measures the first; reactivating the
      window was measured not to move the panel.
- [x] 1.2 `--settings-again <seconds>` in `LaunchOptions`: `showSettingsPage`
      once more at that moment, with `PANEL: maximized=` printed before and
      after. Driven before the fix: `maximized=true`, then `false`.

## 2. The rule

- [x] 2.1 `showSettingsPage`: the group asked for the page first, full screen
      left only when the page has to be made.
- [x] 2.2 The review pane's `openPage` in `MainWindowController+Layout.swift`,
      the same way.

## 3. Proving it

- [x] 3.1 Driven after the fix: the same run prints maximised twice; a run with
      no page yet still prints not maximised after the first open. Both as
      said; the table is in the design.

## 4. Before finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-10: 4,433 tests in 566
      suites, exit 0; `make warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `control-affordances` is what
this change adds to.
