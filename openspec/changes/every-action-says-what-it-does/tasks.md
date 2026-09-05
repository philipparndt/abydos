## 1. One owner for the tip and the hover

- [x] 1.1 `Sources/AbydosApp/Controls/StyledTip.swift` (or beside it) — the
  small owner a view hands its rectangles and `Tip`s to: `tip(at:)`, the show
  on a change of hovered control, the hide on exit, the rectangle in the
  view's own coordinates. The comment says why it exists: three copies of
  `PanelTabStrip`'s plumbing is where the third one starts to differ.
- [x] 1.2 `PanelTabStrip` moved onto it, its own driven verbs
  (`hoverTrailingForTesting`, which answers lit-or-not and the tip's words
  together) green before and after — the strip is the reference this change
  spreads, so it is the thing that must not change behaviour.

## 2. The three areas

- [x] 2.1 `ToolWindowBar` — the rail's buttons drop `toolTip` for the drawn
  tip, each naming the pane it opens and its key where it has one. The hover
  they already draw is untouched, the request having said it is right.
- [x] 2.2 `NavigatorHeaderView` — a tracking area, a hovered-button state, the
  ground behind whichever button the pointer is on (the compact-packages
  pill's on-tint kept and the hover visible against it), and the drawn tip in
  place of the three `button.toolTip` strings.
- [x] 2.3 `RunControl` — a hovered-rectangle state over the run, debug,
  debug-menu, scheme and status rectangles, the ground drawn under it, and the
  drawn tip replacing the `addToolTip` registrations and the tag dictionary;
  Run's ⌃R and Debug's ⌃D taken from where the menu takes them.

## 3. Proving it

- [x] 3.1 One driven door rather than one per area, because it is one
  gesture: `--hover-control` gained an area prefix — `rail:git`,
  `header:collapse`, `run:debug` — with a bare name still meaning the terminal
  strip's own controls, and `hoverChromeForTesting` routing it. Each area
  answers in the shape `hoverStripControlForTesting` already had: lit or not
  lit, and the tip's `reportForTesting`.
- [x] 3.2 Driven on 2026-09-05, a scratch project, a debug build under the
  throwaway id `de.rnd7.abydos.tips`. Twelve hovers in one run:
  `rail:project` *Project ⌘1*, `rail:git` *Git — 1 commit to push — ⌘2* (the
  count on the detail line, where the old string had it after a dash),
  `rail:terminal` *Terminal ⌘J*; `header:collapse`, `header:locate` and
  `header:compact`, the last saying what it is *showing* because it was on;
  `run:run`, `run:debug` *⌃D*, `run:debug-menu`, `run:scheme` *⌃R*; and the
  strip's own `hide` *⌘J*, unchanged by the move onto `TipHost`, with
  `sessions` answering "not here" because nothing was running. Photographed:
  the header's collapse button with the ground under it and the compact pill
  beside it untouched, the ladybird with the ground under it and the play
  button beside it without one, and the drawn tip itself — *Debug* with a ⌃D
  chip — in the theme's own type.
- [x] 3.2a **A finding, and the tips say it rather than hide it.** The Run
  menu declares ⌃R twice — on *Run…*, the chooser, and on the plain *Run* —
  and a menu answers a key with its first matching item, so the play button's
  own command has no key at all. `--menu-keys` measures exactly that: *Run…*
  ⌃R, *Debug* ⌃D, no row for *Run*. Because a tip's shortcut is read from the
  menu item rather than written out beside the control, the play button's tip
  carries no key and the chooser's carries ⌃R — true, where a hand-written
  "⌃R" on the play button would have been a promise the app does not keep.
  The delta spec's scenario says this rather than the ⌃R it first assumed.
- [x] 3.3 The search, and what it leaves. Nothing in the rail, the project
  pane's header or the run control sets `NSView.toolTip` any more. What still
  does, and why it is right that it does: the tree's row cells (`node.detail`
  and the file's path) and the git panes' rows, which are text the pointer
  reads off a list rather than controls; menu items (`NSMenuItem.toolTip`),
  which AppKit draws itself; the panes' own contents — Search's buttons,
  Debug's *Clear the console*, the profiler's pod button, the backlog's row
  entries — and the settings window, which are inside a pane rather than the
  window's chrome. Knowingly left in the chrome: the titlebar capsule and its
  pills (`PillButton`, `TitlebarCapsule`, the language pill), whose tooltips
  are built paragraphs of state; they are not in this request's three areas
  and are worth their own pass rather than a hurried one here.

## 4. Finishing

- [x] 4.1 `Scripts/file-size-allowed.txt` raised for what grew:
  `ProjectNavigatorViewController.swift` 4508 → 4602 (the header's hover, its
  words and the driven verb) and `LaunchOptions.swift` 1607 → 1612 (the
  flag's widened documentation). `MainWindowController+Driving.swift` went
  over the 1100-line limit by the driver door alone, so the door went to
  `+Driving2` instead of the ceiling going up — the debt a ledger records is
  for state that has nowhere else to be. `docs/release-notes-0.14.0.md` has
  the section, the ⌃R finding included.
- [x] 4.2 Green by their exit codes: `make test` 4090 tests in 520 suites,
  exit 0 with the suite's two standing known issues, load 48.7 over 10 cores;
  `make warnings` exit 0, no warnings.
