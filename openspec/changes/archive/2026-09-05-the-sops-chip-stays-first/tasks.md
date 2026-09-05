## 1. The bar

- [x] 1.1 `EditorStatusView.draw(_:)` calls `drawSops()` before `drawLock()`, and `drawSops` takes its origin from the left edge alone, dropping the `lockRect` dependency — the chip keeps its place in every state, because it is the button and the lock is a fact beside it. The drawing comments say why: the chip used to follow the lock and moved the moment it was pressed.
- [x] 1.2 `drawLock` takes its origin from `sopsRect` — at the edge when there is no chip, after the chip's tail plus the standing gap when there is — so a `.env` with no chip keeps its lock exactly where it stands today.
- [x] 1.3 Nothing downstream changes: hit-testing, hover, `resetCursorRects` and `refreshServerToolTip` all read the rectangles and follow the swap on their own; confirmed by reading, not edited.

## 2. Proving it

- [x] 2.1 The driven pair of screenshots retaken on 2026-09-05 with the sops run's own shape — scratch project, an `age` key made for the run, real `sops` 3.13.3, a debug build, `--expand --panel-height 0` (a release build's window and a panel at its remembered height both photograph an editor the report cannot vouch for) — and the position claim checked with pixels rather than eyes: the chip's ink starts at the same column, 14 pt into the bar, in *SOPS · encrypted* standing alone and in *SOPS · decrypted* with the lock after it, and a plain `.env`'s lock stands at that same column when no chip is shown. The reports name the states: encrypted, 23 lines of ciphertext; then decrypted, 8 lines, covers on, revealed.

## 3. Finishing

- [x] 3.1 `Scripts/file-size-allowed.txt` checked against the new `EditorViewController.swift` — the seven lines the comments gained took it to 5328, over the recorded 5321, so the ceiling is raised to 5328 (the reasons-said-aloud debt the file records, one line wider).
- [x] 3.2 Green on 2026-09-05 by their exit codes: `make test` 4076 tests in 519 suites, exit 0, load 19.5 over 10 cores; `make warnings` exit 0 after the ceiling above was raised.

Makes untrue, as a delta spec says outright: the sentence in
`openspec/specs/secret-concealment/spec.md` — *A value is shown only by an
explicit action* — that pins the lock to the left of the bar when the SOPS
chip is beside it, and the *chip beside the secrets lock* wording in
`openspec/specs/sops-files/spec.md` — both replaced by this change's delta
specs.
