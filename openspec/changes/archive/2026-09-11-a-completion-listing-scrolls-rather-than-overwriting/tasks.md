## 1. Name it

- [x] 1.1 A driven run that fills a pane to its last row, types `cd` and two tabs into zsh with the default completion, and prints the screen rows before and after — under both engines, with and without tmux, with the tmux status bar hidden and shown. `--terminal-screen-at`, 2026-09-09; the table is in the design.
- [x] 1.2 The same after a full-screen program (`less`, then `q`) has run in the pane, for the scroll-region case. Correct: the listing under the prompt, nothing lost.
- [x] 1.3 Write into the design which of the three it is — the emulator's line feed at the region's bottom, the rows reported to the pseudo-terminal, or tmux's redraw — or that it does not reproduce and what was ruled out; and if the last, what to ask the reporter (shell, tmux, engine).

## 2. Fix it

- [x] 2.1 Whatever 1.3 named, and nothing that was not named. `scrollUp` advanced `discardedLineCount` even when the scrollback's capacity was zero — the alternate screen — because `ScrollbackBuffer.append` hands the line back rather than storing it and the eviction branch could not tell that from a real shift. It leaves the count alone at capacity zero now. `AlternateScreenScrollTests` captured the bug (`discardedLineCount == 9`, should be 0) and holds the fix.

## 3. Proving it

- [x] 3.1 The unit test is the deterministic proof — the driven run was intermittent by the design's own account. Driven on the fixed build in the failing configuration (our engine, tmux, status bar off, fill then `cd` tab tab): `lines-above=49`, the `seq` output in history and the listing under the prompt, output preserved. The `TerminalScreen` test proves the grid and `line(at:)` agree scroll for scroll.

## 4. Finishing

- [x] 4.1 Say it in the release notes: the paragraph is in the design's release note. Something changed, so it is said.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes. Green 2026-09-10: 4,442 tests in 568 suites, exit 0; `make warnings` exit 0.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what this
change adds to.
