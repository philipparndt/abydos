## 1. Name it

- [x] 1.1 A poster of trackpad events from outside the app: pixel-unit `CGEvent`s, many and small, with the gesture's phase fields, at the terminal pane of the driven window (`trackpad.swift`, scratchpad).
- [x] 1.2 Driven, before the fix: `less -N` on two thousand numbered lines, ten events of two points and one of a hundred. **The top line was 18**: seventeen lines for a gesture of a hundred and twenty points, which at a fifteen-point cell is the old formula exactly — ten for the ten small events, seven for the flick.

## 2. Fix it

- [x] 2.1 `WheelSteps` in the Kit: precise deltas added up, one step per whole cell, the fraction carried; a reversal or a new gesture drops the carry; a notch keeps its formula; a zero delta is nothing rather than one line down.
- [x] 2.2 `TerminalKeys.scrollbackMotion`: ⇧⇞, ⇧⇟, ⇧Home, ⇧End and nothing else.
- [x] 2.3 The view: both wheel paths through the one accumulator, reset on `.began`; the shifted keys taken in `keyDown` on the normal screen only; `scrollHistory` moves the clip a page less a row, or to an end, and leaves the pin to the bounds-change that already computes it.

## 3. Proving it

- [x] 3.1 Driven, after the fix: the same run, the same events. **Top line 2 after the drag and 7 after the flick**: one line for the twenty points, five for the hundred, against seventeen before. The `--mouse` report gained a `WHEEL` line so a run says what arrived and what it became; the table and the lines are in the design.
- [x] 3.2 Driven, the keys: `seq 1 400` into a pane, ⇧⇞ posted from outside, then ⇧End; the clip origin reported before and after each. **7011 → 6395 → 7011** on a 635-point clip: up by the pane less one nineteen-point row, and back to the bottom.
- [x] 3.3 `WheelStepsTests` and `ScrollbackKeysTests`: the arithmetic as claims, including the ten-event drag that was ten lines. Both green in the full run.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-10: 4394 tests in 560 suites, exit 0, load 23 over 14 cores. The first full run exited 2 on `theTerminalsDescriptorsAreNotInheritedByTheNextProgramStarted` finding no descriptor at all — the pty closed under it in the parallel run; alone it passes in 24 ms, and the second full run passed. `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what this
change adds to.
