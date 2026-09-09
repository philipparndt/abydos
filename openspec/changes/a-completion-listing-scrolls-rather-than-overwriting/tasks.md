## 1. Name it

- [x] 1.1 A driven run that fills a pane to its last row, types `cd` and two tabs into zsh with the default completion, and prints the screen rows before and after — under both engines, with and without tmux, with the tmux status bar hidden and shown. `--terminal-screen-at`, 2026-09-09; the table is in the design.
- [x] 1.2 The same after a full-screen program (`less`, then `q`) has run in the pane, for the scroll-region case. Correct: the listing under the prompt, nothing lost.
- [x] 1.3 Write into the design which of the three it is — the emulator's line feed at the region's bottom, the rows reported to the pseudo-terminal, or tmux's redraw — or that it does not reproduce and what was ruled out; and if the last, what to ask the reporter (shell, tmux, engine).

## 2. Fix it

- [ ] 2.1 Whatever 1.3 named, and nothing that was not named. **Open.** 1.3 named the configuration and the code path — our engine, tmux with the status bar hidden, the alternate screen's zero-history whole-screen scroll — and not the instruction. Next: a `TerminalScreen` unit test on that path, then the fix it points at.

## 3. Proving it

- [ ] 3.1 The run from 1.1 shows the rows above the prompt in the scrollback and the listing below it, in the configuration that failed.

## 4. Finishing

- [ ] 4.1 Say it in the release notes, if anything changed.
- [ ] 4.2 `make test` and `make warnings`, both clean, by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what this
change adds to.
