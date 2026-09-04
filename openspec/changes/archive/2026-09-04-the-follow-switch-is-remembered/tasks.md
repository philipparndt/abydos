## 1. Write it

- [x] 1.1 `toggleFollowTerminal` writes `Settings.shared.followsTerminalProject`.

## 2. Read it again, when it moves

- [x] 2.1 The window remembers the stored value it last saw.
- [x] 2.2 `applySettings` adopts a stored value that differs from it, and
  leaves the window alone otherwise.

## 3. Checked

- [x] 3.1 Driven: `--follow-terminal` presses the switch and now says both
  halves — `FOLLOW: window=true stored=true`, where the second was `false`
  before this change and no run could see it, since the flag only ever asked
  the window it had just told.

  **The launch afterwards is not shown, and cannot be from a driven run**: a
  run keeps its preferences in a volatile copy of the real domain — the rule
  that stops a run writing into somebody's settings — so nothing it stores
  outlives it. What is shown is the write that was missing; that a stored
  preference is read at launch is what every other setting already does.
- [x] 3.2 `make test` and `make warnings`, both clean by their exit codes.
  4038 tests in 514 suites, exit 0, at load 8.7 over 14 cores; `make warnings`
  exit 0.
