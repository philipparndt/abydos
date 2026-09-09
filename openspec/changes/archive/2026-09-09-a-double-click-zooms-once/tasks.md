## 1. Name it

- [x] 1.1 Reproduce from outside the process: real mouse events at the title strip, bounds sampled from the window server. Springback every time under the installed binary's SDK marker; the table is in the design.
- [x] 1.2 Tell the two toggles apart by holding the second press: the zoom on the press, the un-zoom after the release.
- [x] 1.3 Measure with the app's handler switched off, under both SDK markers: one zoom that stays, in every run.

## 2. Fix it

- [x] 2.1 Remove the double-click branch from `ColoredView`, and `actsAsTitlebar` with it.
- [x] 2.2 Remove `TitlebarDoubleClick` and `TitlebarDoubleClickTests`, which have no other caller.
- [x] 2.3 The instrument posts the whole gesture — four events, counted 1, 1, 2, 2 — and reads at 0.4 s and 1.2 s.

## 3. Proving it

- [x] 3.1 Driven, handler in place: `--zoom-gesture click` shows the springback the report describes. Seen 2026-09-09: 1920×985 at 0.4 s, 1280×820 at 1.2 s, largest 1920×985.
- [x] 3.2 Driven, handler removed: `--zoom-gesture click+back` shows one zoom that stays and one un-zoom that stays. Seen: 1920×985 at 0.4 s and 1.2 s; 1280×820 at 0.4 s and 1.2 s after the second gesture.
- [x] 3.3 From outside, handler removed: a real double-click zooms once and stays. Seen, plain and after a 30 px drag down: 1920×985 by 0.27 s, still there three seconds later.

## 4. Finishing

- [x] 4.1 The `window-frame` spec says what was found in place of "measured rather than fixed".
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-09: 4358 tests in 555 suites, exit 0, load 19 over 14 cores at the end of the run; `make warnings` exit 0, no warnings.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `window-frame` spec is what
this change makes true.
