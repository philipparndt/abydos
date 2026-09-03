## 1. Draw it everywhere

- [x] 1.1 Split the panel's own trailing controls out of `PanelTabStrip.draw`
  into a function of their own.
- [x] 1.2 Draw the ground only where those controls are, draw the chevron
  unconditionally after it, and guard only the controls.

## 2. Reach it from a driver

- [x] 2.1 `seedMirrorWindowsForTesting(_:)` fills the mirroring strip with
  windows shaped as the mirror makes them, and says what the strip made of it.
- [x] 2.2 `--tmux-tab-fill <count>` seeds them, says what is shown and hidden,
  chooses the first hidden one and says what moved.

## 3. Checked

- [x] 3.1 A driven run at 1100 points: 16 windows, 7 shown, 9 hidden and named;
  the chevron reads `9 ⌄` in tmux's ink at the trailing end of the green bar;
  choosing the first hidden one brings window 7 into view and puts window 0
  behind, still nine hidden.
- [ ] 3.2 `make test` and `make warnings`, both clean by their exit codes.
