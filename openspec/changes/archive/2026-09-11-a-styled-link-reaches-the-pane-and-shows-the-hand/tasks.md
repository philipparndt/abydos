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

## 3a. The click, reversed the same day

- [x] 3a.1 A plain press on a marked link is held; the release within the
      slack opens it and forwards nothing, a drag past the slack begins the
      selection or the forwarded press late. Shift still selects.
- [x] 3a.2 `--terminal-link` sends the release too, and gains `drag`; the
      report says what opened and what was selected.
- [x] 3a.3 Driven: `bare` on the marked link opens once and selects nothing;
      `drag` on it opens nothing; `bare` on the printed address opens nothing.

## 3b. Where it goes

- [x] 3b.1 A tooltip rect over a hovered marked link, reading the address;
      none over a printed address. The driven report says `tip=`.

## 4. Before finishing

- [x] 4.1 Say it in the release notes: the paragraph in the design.
- [x] 4.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-11: 4,446 tests in 568
      suites, exit 0, under a load that reached 42 as the suite ran; `make
      warnings` exit 0; the change valid. Green again after the click was
      reversed: the same 4,446, exit 0, load 19; `make warnings` exit 0.
      And once more with the tooltip: 4,446, exit 0, load 24; `make warnings`
      exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where `terminal` is what this change
adds to.
