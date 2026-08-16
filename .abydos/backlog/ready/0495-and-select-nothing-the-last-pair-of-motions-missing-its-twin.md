# 495. ⌘⇧↑ and ⌘⇧↓ select nothing, the last pair of motions missing its twin

⌘↑ and ⌘↓ go to the start and the end of the file. Hold Shift and nothing
happens at all — no move, no selection. Watched from 0494's `--vertical-nav`
driver, in the app, before the probe was taken out again:

    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⌘⇧↑         caret=8 selection=8..<8 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⌘⇧↓         caret=834 selection=834..<834 “”

`moveToBeginningOfDocument:` and `moveToEndOfDocument:` have cases in
`CodeView.doCommand` (`CodeView.swift:2116`). Their `AndModifySelection` twins
are separate selectors and have none, so the plain keystroke moves and the
shifted one falls to `default:` and is silently dropped.

**This is the third time the same shape has come up, and it should be the
last.** 0494 fixed it for ↑ and ↓ at the edges of a file and, on the way, for
⇧⇞ and ⇧⇟, which were dead for exactly this reason. It deliberately stopped
there: the person reporting it had decided about the arrows, not about the
whole family. Checked across the switch afterwards, these two are now **the
only motions left whose twin is missing** — every other one, from ⌥← to ⇧⇟, has
both.

## Ruled out

- **Doing it inside 0494.** It is two lines and it was tempting. It was left
  because a keystroke nobody has asked about is a decision nobody has made, and
  the item's own scope was the arrows. Filing it is the price of that, and this
  is the file.

## Worth deciding

- **Whether `default:` should be as quiet as it is.** Every one of these three
  was invisible for the same reason: an unhandled selector falls through a
  `default: break` whose comment says staying silent is right, and it *is*
  right — AppKit sends `noop:` and much else. But it is also why a missing
  motion looks exactly like a key that does nothing, three times now. A debug
  build that logged unhandled `move*`/`select*` selectors once each would have
  caught all three in one session, and would say nothing in release. Worth
  weighing against the noise before writing it.

## Steps

- [ ] `moveToBeginningOfDocumentAndModifySelection:` and
      `moveToEndOfDocumentAndModifySelection:` extend the selection to the edge
- [ ] Watched with `--vertical-nav`, or whatever it is called by then, from the
      middle of a file: ⌘⇧↑ selects back to offset 0, ⌘⇧↓ forward to the end
- [ ] Check no other motion is missing its twin, and say in here how that was
      checked rather than that it was
- [ ] Decide about the silent `default:`, and either do it or write down why not
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does — 0494 added two
      requirements about the edges of a file and this belongs beside them
