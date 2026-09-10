## 1. Name it

- [x] 1.1 What k9s sends, captured: k9s against a scratch kubeconfig whose
      servers do not exist, its config directory a scratch copy of the
      maintainer's, in a tmux server of the run's own with `pipe-pane`. True
      black on true aqua, bold, for the row; true black on true orange for the
      crumb. No cluster reached, nothing of the maintainer's touched.
- [x] 1.2 What the pane held, read with `--terminal-pairs`: `indexed(0)` bold
      on `indexed(14)`, drawn as `brightBlack` on bright cyan at 2.86:1 under
      this run's palette — 1.54:1 under AAA. tmux downgraded, the bold rule
      brightened. The proposal's guess — the dim colour, or dim text — was not
      the case, and the design says so.
- [x] 1.3 The painted-pair table for every bundled palette, dark half: thirty
      to forty-two pairs under 3:1 each, all light-on-base or dim-on-colour;
      dark-on-colour passes everywhere. In the design.

## 2. The rule

- [x] 2.1 `TerminalAttributes.brightensBold` in the Kit: bold, a foreground
      among the first eight, and the default background; both renderers ask
      it where they asked `bold`.
- [x] 2.2 Tests: `boldBrightensABaseColourOnTheGroundOnly`,
      `onlyBoldOnTheFirstEightBrightens`, `inverseIsJudgedAfterTheSwap`.

## 3. tmux

- [x] 3.1 `-T RGB` on the client `TmuxMirror.attachArguments` starts;
      `tmuxIsToldTheTerminalShowsRGB`.
- [x] 3.2 Verified in a pane: `#{client_termfeatures}` carries `RGB`, and a
      `38;2;255;0;0` from the shell arrives as `rgb(#FF0000)`.

## 4. The measurement

- [x] 4.1 `SchemeContrast.paintedShortfalls`: black on the fourteen highlight
      colours, dark half, 3:1, each shortfall naming the pair; `pairTable` for
      reading. The dim grey excepted from the backgrounds — the editor
      palette's black on it is 2.99:1, a pair nobody paints.
- [x] 4.2 Tests: `everyBundledPaletteKeepsDarkTextReadableOnWhatProgramsPaint`,
      `aPaintedPairUnderTheFloorIsNamed`.
- [x] 4.3 The AAA dim colour left where it is, the balanced value (#63676F,
      3.0:1 on the ground, 2.84:1 on the worst bright) written into the design
      for the maintainer to decide. Dim itself unchanged, and why.

## 5. Driving and proving it

- [x] 5.1 `--terminal-pairs <row>[@<seconds>]` in `LaunchOptions`.
- [x] 5.2 Driven, after: k9s in the pane, `indexed(0)` bold on `indexed(14)`
      drawn black on cyan at **9.73:1**; a printed `1;30;46m` at 7.76:1 beside
      a bold black on the ground still brightened at 3.76:1 — the prompt case
      unchanged.

## 6. Before finishing

- [x] 6.1 Say it in the release notes: the paragraph is in the design.
- [x] 6.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-10: 4,429 tests in 565
      suites, exit 0; `make warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what
this change adds to.
