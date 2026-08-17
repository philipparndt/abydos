## Why

`.abydos/backlog/spec/editor.md`, under "⌃B and ⌃F move the caret a character, and so
do ← and →", says:

> A character is a composed character, so an emoji or a letter with a combining mark
> is one step and not two.

Half of that is true. The alignment all four horizontal keys go through is
`Rope.alignToBoundary`, and all it does is walk back over UTF-8 **continuation
bytes** — which is **code-point** alignment, not grapheme alignment. An emoji is a
single code point, so `🙂` is one step and the spec's scenario is right. `e` + U+0301
is two code points, and neither begins with a continuation byte, so the caret stops
between the letter and its accent: where no caret should ever be, and where the next
keystroke edits half a character. The same goes for a flag, a skin-tone sequence, or
anything joined with a ZWJ.

Watched with `--emacs-nav` on a line whose second character is a decomposed `é`
starting at offset 13:

    EMACS: PROBE mark  caret=13 selection=13..<13 “”
    EMACS: ⌃F          caret=14 selection=14..<14 “”

13 → 14, not 13 → 15.

Nothing here is new — the alignment has been code-point alignment since it was
written. What is new is knowing it, and that the spec claims otherwise.

From `.abydos/backlog/open/0504-a-decomposed-accent-is-two-steps-of-f-and-the-spec-says-one.md`,
found while doing 0503.

## What Changes

- ←, →, ⌃B and ⌃F step over a whole grapheme, with or without Shift. They are one
  function, `moveHorizontally`, which every one of them reaches.
- ⌫ and ⌦ over a decomposed accent are probed first, and either fixed with the motion
  or ruled out here. They very likely leave the base letter behind or the mark
  orphaned, and they are the same question — worth one item rather than two.
- The sentence in `spec/editor.md` about a combining mark **becomes true rather than
  changes**. A caret that can land inside a character is a bug, not a decision.

## Capabilities

### New Capabilities
<!-- None. The requirement exists and is untrue, which is the point. -->

### Modified Capabilities
- `editor`: "⌃B and ⌃F move the caret a character, and so do ← and →" — the sentence
  about a combining mark becomes true rather than changes, and gains the scenario
  that would have caught it. A requirement for deleting is added beside it, so that
  the two cannot answer the boundary question differently.

## Impact

- `Rope.alignToBoundary`, or only its caller in `moveHorizontally` — that is the
  design decision, since `alignToBoundary` is used for more than the caret and a
  wider definition of a boundary may be wrong for some of those.
- Deletion, if the probe says it shares the fault.
- `.abydos/backlog/spec/editor.md` — the requirement quoted above, and its emoji
  scenario, which stays true either way.
- Not affected, and worth knowing why: `\r\n` is one grapheme and two code points.
  0503's ⌃O works because the step back does not swallow the pair. **The bug and the
  thing that made ⌃O correct are the same fact**, so ⌃O must be re-checked here.
