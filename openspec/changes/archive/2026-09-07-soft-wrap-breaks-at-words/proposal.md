## Why

**Soft wrap cut lines in the middle of words.** `WrapLayout` filled each
visual row by display width and cut at the column edge, so a README read with
word wrap on broke `sentence` into `sen` and `tence` wherever the edge fell —
the one thing soft wrap exists to prevent, since its purpose is prose that
reads. Asked for on 2026-09-07: "in e.g. markdown files, the lines are broken
in the middle of a word when word wrap is enabled. This destroys the reading
flow. We should only break at words and not in the middle of a word."

No originating backlog item: asked for directly.

## What Changes

- **A row is cut after the last whitespace that follows a word**, so the word
  moves down whole and the whitespace stays at the end of the row above.
- **Leading indentation is not a place to cut**: a row of nothing but spaces
  would be the result.
- **A word longer than the row is cut at the edge**, as before, because there
  is nowhere else.
- The three answers the layout gives — how many rows a line takes, which
  units are on a row, which row an offset is on — come from one walk, so they
  cannot disagree.

## Capabilities

### New Capabilities

<!-- None. -->

### Modified Capabilities

- `editor`: gains the requirement that soft wrap cuts at words.

## Impact

- `Sources/AbydosKit/Text/WrapLayout.swift` — `rowStarts(in:columns:tabWidth:)`
  and the three functions over it.
- `Tests/AbydosKitTests/WrapLayoutTests.swift` — a suite for the cuts.
- Cost: still one pass over the line's units per question, as before.
