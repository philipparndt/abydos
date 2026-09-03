## 1. The list in a window of its own

- [x] 1.1 `RunningSessionsPalette`: an `NSPanel` host, titled and
  full-size-content with a hidden title and transparent title bar, holding an
  existing `RunningSessionsController` as its content. `SymbolPanel` became
  `PalettePanel` in `Controls`, so the two palettes share one window class
  rather than one of them keeping a copy.
- [x] 1.2 `show(over:)` sizes it to what the list wants — the controller holds
  its own size by constraints, so the window is set to `wantedSize` and the
  *placement* is what gets clamped: centred horizontally on the parent, near
  its top, and never hanging off its edges.
- [x] 1.3 Escape and losing key put it away; the key that opened it, pressed
  again, closes it, since a child window's responder chain does not reach the
  window controller and the menu item is therefore disabled while it is up.

## 2. Both routes, one list

- [x] 2.1 `PanelRunningSessions.showPalette(over:)` builds the controller the
  way `show(from:of:)` does — the same `firstSlugs`, `reach` and `onChoose` —
  and holds the palette beside the popover.
- [x] 2.2 Opening either route closes the other, and `RunningSessionsHost` is
  what the presenter holds them both by.
- [x] 2.3 The clock that keeps the counts honest ticks for whichever is open.

## 3. The key

- [x] 3.1 A `Running Sessions` item in the Agent menu, ⇧⌘A — free: at ⇧⌘ the
  taken letters are b c f g j k l m n o p r s t u v w z, and ⌘A alone is Select
  All.
- [x] 3.2 `MainWindowController.showRunningSessions(_:)` asks the panel to show
  the palette over its window, and leaves the panel shut.

## 4. The popover advertises it

- [x] 4.1 The filter row draws `⇧⌘A` dimmed at its trailing edge, and the
  field's trailing anchor ends at the label rather than the edge.
- [x] 4.2 The palette asks for the same row with no shortcut.

## 5. Driven and checked

- [x] 5.1 `--running-sessions-palette <seconds>` opens it the way the key does;
  `--running-sessions-keys` follows either route.
- [x] 5.2 Driven, not unit-tested: this is `AbydosApp`, which has no test
  target, and every claim here is about windows. The run says the rows, the
  size, that it is centred, how far below the top it sits, and which host has
  it — so "opening one closes the other" is a claim the output can carry.
- [x] 5.3 A `sessions-key` capture beside `sessions` in `Scripts/screenshots.sh`.
- [x] 5.4 `make test` and `make warnings`, both clean by their exit codes —
  4023 tests in 512 suites passed in 57.6 s with the suite's two standing known
  issues, at load 13 over 14 cores, and both runs returned 0.
