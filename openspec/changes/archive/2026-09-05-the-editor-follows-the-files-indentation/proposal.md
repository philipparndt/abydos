## Why

**⇥ inserts a tab character whatever the file it is pressed in.** Open a
two-space `values.yaml` — every line indented by two spaces, the way YAML
must be — press ⇥ on a fresh line and a tab goes in: a file that was one
convention is now two, and the diff says a tab was typed on a line nobody
touched. Select a block and press ⇥ and it is worse: `shiftLines` indents
every selected line with a *hardcoded* `"\t"`. Return is the only key that
asks the file — `ReturnIndent.usesTabs` samples the buffer and matches the
habit — and even it takes the space *width* from the tab-display setting
rather than from the file, so return in a two-space file indents by the
setting's four.

Reported on 2026-09-05: "we should detect if a file is indented by tabs or
by spaces. This should be shown in the editor footer, it should be possible
to switch it. When the file is indented by spaces, and pressing tab we should
insert the right amount of spaces instead."

No originating backlog item: asked for directly on 2026-09-05.

## What Changes

- **A file's indentation is a fact about it, read from what the file already
  does.** At open — bounded, like the SOPS look — the head of the buffer says
  which the file is: *tabs*, or *spaces, and how many* (the most common
  leading run, ties to the narrower). A file with no indentation yet falls
  back to the app's tab width as spaces, which is what return already did.
  `ReturnIndent.usesTabs` folds into the new `IndentStyle` — one detector,
  one suite — and the detection is re-read whenever the buffer is replaced
  wholesale (a decrypt, a lock, an external reload), because the new text is
  a new file's worth of habit.
- **The footer says it, on the right, and a menu switches it.** A chip in
  the footer's right side, between the caret position and the language,
  reading *Tabs* or *Spaces: 2* — the file's own width. Pressing it opens a
  menu: *Indent with Tabs*, then *Indent with 2/4/8 Spaces*, with the file's
  own unusual width offered beside the standing ones, the current style
  ticked.
- **Choosing converts the file.** The buffer's indentation is converted to
  the chosen style, level by level: one leading level of the old style — a
  tab, or the old width in spaces — becomes one level of the new, alignment
  after the first non-blank left alone, a partial level keeping its spaces,
  one edit so one ⌘Z returns the file to what it was. The chosen style
  becomes the one that is inserted from here, and everything that inserts
  follows at once.
- **⇥, ⇧⇥, block indent and return all insert the file's own unit.** ⇥ with
  no selection inserts one level — a tab in a tabs file, the style's width in
  spaces in a spaces file; over a selection it shifts every line by that
  same unit rather than a hardcoded tab; ⇧Tab takes one level off — a tab,
  or up to the style's width in spaces; and return's auto-indent, which
  already matched the kind, now takes its width from the file as well.

*Amended on 2026-09-05, the same day, from a first cut that put the chip on
the left as a press-toggle that converted nothing: asked for directly —
"the tabs/spaces toggle should be on the right side of the toolbar and it
shall show a menu. It shall then also convert the file when switched."*

## Capabilities

### New Capabilities

- `indentation`: how a file's indent style is detected, said in the footer,
  chosen from a menu, converted to, and what ⇥, ⇧⇥ and return insert.

### Modified Capabilities

<!-- None: no existing requirement covers ⇥, ⇧⇥ or return's indent — the
`editor` spec has the comment token's indent and nothing about ⇥; the chips
of `sops-files` and `secret-concealment` are other facts. The new capability
is the first home this behaviour has. -->

## Impact

- `Sources/AbydosKit/Text/IndentStyle.swift` — new, beside `ReturnIndent` and
  `LineIndent`: the style, the bounded detection, the unit one level of it
  is, the menu's offered widths, and the level-by-level conversion. Tested
  without a window; `ReturnIndent.usesTabs` and its four test claims move
  here.
- `Sources/AbydosApp/Editor/CodeView.swift` — the style is held once per
  document rather than re-sampled per keypress: read at `load(document:)`
  and in `replaceAllText`, set by the menu's choice through
  `convertIndentation(to:)`; `usesTabsForIndent` and the hardcoded `"\t"` in
  `shiftLines` go.
- `Sources/AbydosApp/Editor/EditorViewController.swift` — the chip in the
  footer's right-aligned row beside the language, with hover, cursor,
  tooltip and the menu; the conversion routed to the view that owns the
  buffer; state pushed through `refreshStatus` like the lock's and the SOPS
  chip's. The server chip's room now begins after the left chips' extent, so
  the narrower right group cannot overlap them on a narrow window.
- `Sources/AbydosApp/Editor/EditorAreaController.swift` — the menu's choice
  and the status push, beside the SOPS chip's.
- Driver: `--indent <steps>` — `report`, `menu`, `choose:tabs` or
  `choose:<width>`, `tab`, `return`, `caret:<line>`, `type:<text>`,
  `shift`/`unshift:<from>-<to>`, `undo`, `settle` — modelled on `--sops`.
- No new cost: one bounded read at open and at wholesale replacement; the
  per-keypress sampling that `usesTabsForIndent` did on every return goes
  away, and a conversion is one rope replace, the cost of a paste.