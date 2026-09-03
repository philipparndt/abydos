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
- [ ] 2.3 `make test` and `make warnings`, both clean by their exit codes.
