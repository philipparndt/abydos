## 1. Name it

- [ ] 1.1 By hand, on a machine with k9s and a cluster: `tmux pipe-pane -o
      'cat > k9s.bytes'` on a pane about to run k9s, the contexts view opened,
      and the SGR sequences around the selected row and the `<contexts>` crumb
      read out of the file. Which pair it is — `brightBlack` on `brightBlue`,
      the default foreground dimmed over it, or another — written into the
      design, and the sequences kept for 5.2.
- [ ] 1.2 The painted-pair table for every bundled palette, printed by the
      measurement in 2.1 before anything is changed, in the design: which
      palettes fail which pairs, the AAA ones first.

## 2. The measurement

- [ ] 2.1 `SchemeContrast.paintedShortfalls(in:)`: the five text colours on the
      sixteen backgrounds, both grounds, held to 3:1, each shortfall naming the
      pair; and `pairTable(in:)` for the full sixteen-by-sixteen, for reading.
- [ ] 2.2 `floor(for: .brightBlack)` is 3:1 whatever the promise, with the
      reason beside it.
- [ ] 2.3 Tests, as claims: `theDimColourIsHeldOnBothGroundsItIsDrawnOn`,
      `aPaintedPairUnderTheFloorIsNamed`, `everyBundledPaletteIsLegibleOnWhatProgramsPaint`
      — the last one red until 3 is done, and the design says so.

## 3. The palette

- [ ] 3.1 `wcag-level-aaa.json`: `brightBlack` dark moved in lightness, hue
      kept, to 3:1 on the ground and 3:1 on `brightBlue`, `brightCyan` and
      `brightYellow`; the light half checked the same way and moved if the
      measurement says so.
- [ ] 3.2 Any other bundled palette 1.2 named, fixed the same way or its
      exception stated in the file and in the design.

## 4. Dim

- [ ] 4.1 `TerminalDim.alpha(foreground:background:)` in the Kit: 45% while the
      blend keeps 3:1 against the background, 1 otherwise; tests
      `dimOverTheGroundIsFortyFivePercent`, `dimOverALightBackgroundIsNotFadedIntoIt`.
- [ ] 4.2 Both renderers ask it per dim cell, with the cell's resolved
      background; `TerminalPalette.dimAmount` stays the 45%.

## 5. Driving and proving it

- [ ] 5.1 `--terminal-pairs <row>` in `LaunchOptions`: each run of cells on the
      row with the foreground and background the renderer resolves and their
      ratio.
- [ ] 5.2 Driven: the k9s sequences from 1.1 and the painted pairs printed
      with `--send-bytes` under the AAA palette and the default one, before and
      after 3 and 4, both renderers; the ratios in the design's table, a
      picture beside each.

## 6. Before finishing

- [ ] 6.1 Say it in the release notes: the paragraph is in the design.
- [ ] 6.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what
this change adds to.
