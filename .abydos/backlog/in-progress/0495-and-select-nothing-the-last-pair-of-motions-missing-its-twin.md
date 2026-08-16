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

## Watched in the app

0494's `--vertical-nav` driver, extended with the four ⌘ keystrokes. They are
pressed from **line 3 of 7** rather than from an edge: from the top ⌘⇧↑ would
select nothing and read exactly like the dead key it used to be, and from the
bottom so would ⌘⇧↓. The caret is put back to the same place before each one,
so the four lines are four independent presses and not a run.

The scratch file is 0494's again — seven lines, the first 723 characters, **no
trailing newline** — so the offsets line up with the report quoted at the top
of this item: line 3 starts at 771, line 6 at 830, the file ends at 863.

    $ build/Abydos.app/Contents/MacOS/Abydos --open …/vert --file …/vertical.txt --vertical-nav

    VERT: word wrap is off
    VERT: at 3@4      caret=775 selection=775..<775 “”
    VERT: ⌘↑          caret=0   selection=0..<0 “”
    VERT: at 3@4      caret=775 selection=775..<775 “”
    VERT: ⌘⇧↑         caret=0   selection=0..<775 “one word001 word002 …
                                                   third line of the file
                                                   four”
    VERT: at 3@4      caret=775 selection=775..<775 “”
    VERT: ⌘↓          caret=863 selection=863..<863 “”
    VERT: at 3@4      caret=775 selection=775..<775 “”
    VERT: ⌘⇧↓         caret=863 selection=775..<863 “th line of the file
                                                     fifth line of the file
                                                     sixth lines
                                                     seventh and last line of the file”

The `…` in the ⌘⇧↑ line is 700-odd characters of `word004 word005 …` elided by
hand; nothing else here is edited. Before this change all four of those lines
read `caret=775 selection=775..<775 “”` for the two shifted presses — the
report the driver prints when a keystroke does nothing at all, which is what
the four lines at the top of this item are.

So: the caret lands on the same offset with Shift as without — 0 for up, 863
for down — and Shift decides only whether the text between there and 775 comes
with it. That is the same sentence 0494 wrote for ⇧↑ and ⇧⇟.

**Run twice, and soft wrap makes no difference to these four.** The whole
unwrapped run is above; the same run with wrap on prints byte-identical ⌘ lines
(the earlier keystrokes differ, as 0494 documented: `↑` from `0@400` is 197
wrapped and 0 unwrapped). It could not be otherwise — `moveToDocumentEdge` is
offset 0 and `utf16Count` and never asks about a row — but the setting persists
between launches and the run says which mode it is in, so it was cheap to
confirm rather than argue.

## Estimate

2026-08-16 10:04 — about an hour left

## Steps

- [x] `moveToBeginningOfDocumentAndModifySelection:` and
      `moveToEndOfDocumentAndModifySelection:` extend the selection to the edge
- [x] Watched with `--vertical-nav`, or whatever it is called by then, from the
      middle of a file: ⌘⇧↑ selects back to offset 0, ⌘⇧↓ forward to the end
- [ ] Check no other motion is missing its twin, and say in here how that was
      checked rather than that it was
- [ ] Decide about the silent `default:`, and either do it or write down why not
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does — 0494 added two
      requirements about the edges of a file and this belongs beside them
