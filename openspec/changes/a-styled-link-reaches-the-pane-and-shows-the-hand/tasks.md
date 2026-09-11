## 1. Through tmux

- [x] 1.1 `TmuxMirror.attachArguments`: `-T RGB,hyperlinks`, with the comment
      saying what tmux does to a hyperlink bound for a client without it.
- [x] 1.2 `TmuxMirrorTests` and `PaintedPairTests`: the arguments as they now
      are; a test that the features name `hyperlinks`.
- [x] 1.3 `TerminalEmulator` test: `ESC ] 8 ; id=tmux1 ; url ESC \` marks the
      cells that follow with `url`, and the id is not in the address.

## 2. Without tmux

- [x] 2.1 `PseudoTerminalEnvironment`: `FORCE_HYPERLINK` defaulted to `1`, with
      the reason beside `TERM` and `COLORTERM`.
- [x] 2.2 `PseudoTerminalWriteTests`: a pane finds `FORCE_HYPERLINK=1` and
      still `TERM_PROGRAM=Abydos`; a `0` somebody exported is kept.

## 3. The pointer

- [x] 3.1 `link(atWindowPoint:flags:)`: the marked lookup first and always; the
      printed scan only with ⌘. `updateHoveredLink` asks on every move.
- [x] 3.2 `--terminal-link <row>:<column>:hover`: the hover with no modifier,
      through the same path, in `LaunchOptions+Parse`, `BottomPanel+Driving`
      and `linkReportForTesting`.
- [x] 3.3 Driven, on a scratch project: a marked link and a printed address on
      screen, `hover` on each — the first underlined with a hand, the second
      not; ⌘ on the second underlined. The lines are in the design, and the
      first of them is the tmux proof too: the link was written inside the
      pane's tmux and arrived marked.

## 4. Before finishing

- [x] 4.1 Say it in the release notes: the paragraph in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-11: 4,446 tests in 568
      suites, exit 0, under a load that reached 42 as the suite ran; `make
      warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `terminal` is what this change
adds to.
