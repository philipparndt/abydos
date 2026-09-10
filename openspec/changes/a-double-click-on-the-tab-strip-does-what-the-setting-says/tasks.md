## 1. The setting

- [x] 1.1 `TabStripDoubleClick` in the Kit — `maximize`, `localScratch`,
      `globalScratch` — and `Settings.tabStripDoubleClick` on a string key with
      `maximize` registered as the default.
- [x] 1.2 Tests: `theDefaultIsToExpandTheEditor`,
      `anUnknownStoredValueReadsAsTheDefault`.

## 2. The strip

- [x] 2.1 `EditorTabBar+Mouse.swift`: the double-click over the empty part
      reads the setting and calls `onMaximize`, `onNewScratch` or
      `onNewGlobalScratch`; a double-click on a tab unchanged.
- [x] 2.2 `EditorViewController+Tabs.swift`: `onNewGlobalScratch` wired to
      `newScratch(global: true)` if it is not already.

## 3. The page

- [x] 3.1 A `.choice` in `SettingsPaneController.editorRows`: *Double-click on
      the tab strip*, the three options worded as what they do, help naming
      where the other two remain reachable. **First landed on the Terminal
      page**: the edit anchored on the first `sections` array after
      `editorRows`, which is `terminalRows`'s, and the maintainer saw it there.
      Moved; `--settings-says` now answers `Editor ▸ Double-click on the tab
      strip` and finds no such row on Terminal.

## 4. Driving and proving it

- [x] 4.1 `--tab-double empty` for the strip's empty part, printing
      `editorMaximized=` or the scratch that opened.
- [x] 4.2 Driven under each of the three values on a scratch project, the
      defaults domain seeded with the value: maximised and back; a scratch in
      the project's directory; a scratch in the global directory. Recorded in
      the design with the paths, and what the runs left in `~/.config` removed.

## 5. Before finishing

- [x] 5.1 Say it in the release notes: the paragraph is in the design, naming
      the old behaviour and where it went.
- [x] 5.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-10: 4,433 tests in 566
      suites, exit 0; `make warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `editor` spec is what this
change adds to.
