## 1. Finding an address

- [x] 1.1 `TerminalLine.webAddresses()` in the Kit: over the cells, skipping
      wide trailers, mapping text offsets back to columns; `http://`,
      `https://`, `mailto:` to whitespace, a quote or an angle bracket; trailing
      `.,;:!?` dropped; a trailing `)` dropped only when unbalanced.
- [x] 1.2 Tests, named as claims: `anAddressAtTheEndOfASentenceLeavesTheFullStop`,
      `aWikipediaAddressKeepsItsBracket`, `aBracketTheAddressDidNotOpenIsNotPartOfIt`,
      `anAddressInAngleBracketsComesOutWithoutThem`, `twoAddressesOnOneLineAreTwo`,
      `aWideCharacterBeforeTheAddressDoesNotShiftItsColumns`,
      `anAddressWithoutASchemeIsNotOne`, `aLineWithNoAddressFindsNone`.

## 2. ⌘ and the pointer

- [x] 2.1 `hoveredLink` becomes the range under the pointer — row, columns,
      URL — set only while ⌘ is in the event's flags, cleared otherwise; a
      marked link's id first, the row's `webAddresses()` second.
- [x] 2.2 `flagsChanged` on the view, so ⌘ pressed over a still pointer draws
      the underline; the cursor a hand only while there is a range.
- [x] 2.3 One row scanned per pointer move, and the scan skipped when the row
      and its text are what they were.

## 3. Drawing it

- [x] 3.1 CoreGraphics: a pass after the rows in `drawMarked` that rules under
      the hovered range at the SGR underline offset, in the row's foreground.
- [x] 3.2 Metal: the `isLinked` test on the hovered id replaced by the range,
      and the underline on bare hover gone with it.

## 4. Opening it

- [x] 4.1 `mouseDown`: ⌘-click over a range opens through `LinkOpener` and
      starts no selection; a bare click over a marked link selects, as over
      text; a ⌘-click over a link is not forwarded to a program tracking the
      mouse, and a ⌘-click over anything else goes where it went before.
- [x] 4.2 `LinkOpener`: `NSWorkspace` on a real run, a printed line on a
      driven one.

## 5. Driving and proving it

- [x] 5.1 `--terminal-link <row>:<column>[:click]` in `LaunchOptions`: the
      pointer there with ⌘ held, `LINK row= columns= url= underlined=` printed,
      and with `:click` what would have opened.
- [x] 5.2 Driven, on a scratch project: an address printed with `--send-bytes`
      on a row with a wide character before it, under both renderers and inside
      `tmux` with the mouse on — the columns, the address, the rule, the open,
      and a bare click that selects. Recorded here: the table is in the
      design — the address after an emoji at columns 3…41 under both
      renderers, the Wikipedia bracket kept and the sentence's dropped,
      `opened=1 selecting=false` for ⌘-click with tracking on and off,
      `opened=0 selecting=true` for a bare click, the marked link over its
      marked cells, and no browser opened by any of it.
- [x] 5.3 The open question — a wrapped address — decided on the same run and
      written into the design: two rows, because the emulator records no
      soft-wrap on a line and the join cannot be made honestly without it.

## 6. Before finishing

- [x] 6.1 Say it in the release notes: the paragraph is in the design.
- [x] 6.2 `make test` and `make warnings`, both clean, by their exit codes;
      `openspec validate` on the change. Green 2026-09-10: 4,423 tests in 564
      suites, exit 0; `make warnings` exit 0; the change valid.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`, where the `terminal` spec is what
this change adds to.
