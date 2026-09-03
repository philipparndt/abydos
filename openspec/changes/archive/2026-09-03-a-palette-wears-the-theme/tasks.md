## 1. The window wears it

- [x] 1.1 `PalettePanel` sets its appearance and its ground from
  `Theme.current` on `orderFront` and on `makeKeyAndOrderFront`.
- [x] 1.2 The running-sessions palette stops setting it at construction, and
  keeps applying the theme to the ground its own list is drawn on.

## 2. Checked

- [x] 2.1 A driven run on the light theme: the band, the field's bezel and the
  rows are one palette in the picture.
- [x] 2.2 The same run on the dark theme, so the fix is not a light constant
  written in.
- [x] 2.3 `make test` and `make warnings`, both clean by their exit codes.
  4023 tests in 512 suites, exit 0, at load 25 over 14 cores on 2026-09-03; `make warnings` exit 0. Two wall-clock classifications were replaced to get there — see `a-deadline-is-named-not-timed`.
