## 1. The style, in the engine

- [x] 1.1 `Sources/AbydosKit/Text/IndentStyle.swift` — `IndentStyle` (`.tabs`,
  `.spaces(width:)`), the bounded detection (kind by line counts with tabs
  winning ties, width by most common leading space run with ties to the
  narrower, no evidence falling back to the given width), the unit one level
  of it is, and the chip's words in the one place the chip, the tooltip, the
  report and the spec all read. Beside `ReturnIndent` and `LineIndent`.
- [x] 1.2 `ReturnIndent.usesTabs` folded into it — one detector, one suite —
  and its four test claims (a tabbed file is tabs, a spaced file is not, a
  file with no indentation takes the fallback, an empty text too) moved into
  `IndentStyleTests` beside the width claims: two spaces, four spaces with a
  six-space continuation line, a tie going to the narrower, a mixed file
  staying tabs, the unit strings.

## 2. The view and its keys

- [x] 2.1 `CodeView` holds the style: read in `load(document:)` from the same
  8 KB window `usesTabsForIndent` sampled per keypress — that property is
  deleted — and in `replaceAllText`, whose whole-text replacements (a decrypt,
  a lock, an external reload) are a new habit to read and let a chip choice
  go. `toggleIndentStyle()` is the chip's door; the style the file was found
  with is kept beside the current one, so a press to spaces arrives at the
  width the file had when it had one.
- [x] 2.2 The insertion paths read the style: `indentSelectionOrInsertTab`
  inserts the unit, not `"\t"`; `shiftLines` hands `LineIndent` the unit and
  the style's width instead of the hardcoded tab and the display setting;
  return's `ReturnIndent.result` and the closing brace's `dedented` take
  their kind and width from the style.

## 3. The chip

- [x] 3.1 `EditorStatusView`: an indent chip after the lock — *Tabs* or
  *Spaces: 2*, text-only as the language chip is — with hover, pointing
  cursor, a tooltip saying that only what is inserted next changes, and a
  press, all wired the way the lock's and the SOPS chip's are. State pushed
  through `refreshStatus` beside the others; the press routed through the
  area controller as `pressSops` is.
- [x] 3.2 The server chip's room begins after the left chips' extent — the
  left chips drawn before `drawServer`, which reads `leftChipsExtent()` —
  so an always-present third chip cannot overlap the server's name on a
  narrow window. The old margin stands when no chip is shown.

## 4. Proving it

- [x] 4.1 The driver: `--indent <steps>` with `report` (the chip's words and
  the buffer's head, tail on a longer file, tabs as `→`), `press`, `tab`,
  `return`, `caret:<line>`, `type:<text>`, `shift:<from>-<to>` and
  `unshift:<from>-<to>`, `settle`. The block steps went through the group's
  `indentForTesting` — the same door the keys go through — because the older
  `--indent-block` verb does not flush before a run is stopped and its
  reports were lost to the buffer.
- [x] 4.2 Driven on 2026-09-05, files made for the run, a debug build under
  the throwaway id `de.rnd7.abydos.indent`:
  - *The two-space yaml:* `values.yaml` opens reading *Spaces: 2*; ⇥ at
    line 1 inserts two spaces (`  values:`); the press reads *Tabs* and ⇥
    then inserts a tab (`→  values:`); the second press reads *Spaces: 2*
    again — the file's own width back, not the setting's four.
  - *Return follows the width:* a block opener typed on the yaml, return,
    and the new line reads two spaces — not the setting's four.
  - *The tabs file:* `Main.swift` opens reading *Tabs*; ⇥ inserts a tab;
    return after an opening brace indents a tab.
  - *The block:* lines 2–3 of the yaml shifted to four spaces and back to
    two with `unshift` — one level of the file's unit each way, where a
    hardcoded tab went in before.
  - *The footer, photographed:* a window capture read with Vision —
    *Spaces: 2* in the footer row at the editor's left edge on the yaml,
    and on a `.env`, whose values conceal, the lock first (*Secrets
    hidden*) with *Spaces: 4* after it — the `.env` having no indentation
    yet, which is the fallback width said out loud. The position claims
    checked against the bounding boxes, not the eyes.

## 5. Finishing

- [x] 5.1 `Scripts/file-size-allowed.txt` raised for what grew:
  `EditorViewController.swift` 5372 → 5533 (the chip, its state, the press
  and the driver), `CodeView.swift` 4585 → 4631 (the held style, its
  detection points, the doors), `AppDelegate.swift` 3769 → 3775 and
  `LaunchOptions.swift` 1598 → 1602 (a dispatch and a flag).
  `EditorAreaController.swift` at 1051 joined the over-the-aim notes, under
  the limit. The sops skip's *Spaces: 2* claim above is this change's
  ceiling note in one line. Said in `docs/release-notes-0.14.0.md`, with
  the return-width change named so it is not found as a bug, and the
  earlier encrypt-skip given its paragraph there too.
- [x] 5.2 Green by their exit codes: `make test` 4082 tests in 520 suites,
  exit 0 with the suite's standing two container-runtime issues, load 59.18
  over 10 cores; `make warnings` exit 0, no warnings.
## 6. The amendment: the chip moves right, opens a menu, and converts

*Sections 1–5 above are this change's first cut and stand as they were done —
the chip on the left after the lock, a press that toggled the kind and
converted nothing. Asked for the same day: "the tabs/spaces toggle should be
on the right side of the toolbar and it shall show a menu. It shall then also
convert the file when switched." What that cost is here, and the delta spec,
the proposal and the design say the amended behaviour rather than the first
cut's.*

- [x] 6.1 `IndentStyle` gained the two rules the menu needs, both in the
  engine so the menu and the driven report read one source:
  `offeredWidths(currentWidth:)` — the standing 2, 4 and 8 with the file's own
  width beside them when it is not one of them — and `converted(_:from:to:)`,
  which walks a line's leading whitespace and turns one level of the source
  into one level of the target: alignment after the first non-blank left
  alone, a partial level keeping its spaces, a tabs file's stray leading
  spaces kept as they are, and converting to what it already is changing
  nothing. Eight more claims in `IndentStyleTests`, 15 in the suite.
- [x] 6.2 `CodeView.convertIndentation(to:)` — one rope replace, so one ⌘Z
  takes the file back — with the chosen style set *after* the replacement,
  over the re-read `replaceAllText` does: a conversion is the one wholesale
  replacement whose style is known without reading, and a file converted to
  tabs that has no indented line yet must not fall back to spaces the moment
  its own menu item is taken. Undo, redo and a history travel re-detect, so
  the undo of a conversion takes the chip back with the file.
- [x] 6.3 `EditorStatusView`: the chip left the left group and joined the
  right-aligned row between the caret position and the language — where the
  two menu-openers now stand side by side — and the press pops
  `makeIndentMenu()` (*Indent with Tabs*, then the offered widths, the
  current style ticked) instead of toggling. The left chips' extent still
  bounds the server chip's room, which the first cut added and this keeps.
- [x] 6.4 The driver's `--indent` steps followed: `press` became `menu` (the
  offer alone) and `choose:tabs` / `choose:<width>` (the pick), and `undo`
  joined them; the report says the chip's words, the menu's offer with the
  ticked style, and the buffer's head.
- [x] 6.5 Driven on 2026-09-05, files made for the run under the agent
  scratchpad, a debug build under the throwaway id
  `de.rnd7.abydos.indent-amend`:
  - *The two-space yaml:* `values.yaml` reports
    `chip=Spaces: 2 menu=Tabs/2/4/8 ticked=Spaces: 2`; `choose:tabs`
    converts every level to a tab (`→name: abydos`, `→→- 8080`) and the chip
    reads *Tabs*; ⇥ on line 2 inserts a tab; one `undo` takes the tab back
    and the next takes the whole conversion back — two spaces again, chip
    *Spaces: 2*, the chip following the file through the undo.
  - *The tabs file:* `Main.swift` reports *Tabs*; `choose:4` gives every
    level four spaces and the chip reads *Spaces: 4*; ⇥ on line 3 inserts
    four spaces; two undos return the tabs and the chip with them.
  - *The unusual width:* `three.yaml`, indented with three spaces, reports
    `menu=Tabs/2/3/4/8 ticked=Spaces: 3` — the file's own width offered
    beside the standing ones.
  - *The footer, photographed:* a window capture on the yaml reads
    *1:1*, *Spaces: 2*, *YAML* along the footer's right side — the chip
    between the caret position and the language, where the request put it.
- [x] 6.6 `Scripts/file-size-allowed.txt` raised for what the amendment cost:
  `EditorViewController.swift` 5533 → 5581 (the menu, its builder and the
  chip's move to the right group), `CodeView.swift` 4631 → 4638 (the
  conversion door and the re-detect on undo). `docs/release-notes-0.14.0.md`
  says the amended behaviour — the menu, the conversion and the one undo —
  rather than the first cut's toggle.
- [x] 6.7 Green by their exit codes: `make test` 4090 tests in 520 suites,
  exit 0 with the suite's two standing known issues, load 79.8 over 10 cores;
  `make warnings` exit 0, no warnings.
