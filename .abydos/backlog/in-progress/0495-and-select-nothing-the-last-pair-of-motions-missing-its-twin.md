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
hand; nothing else here is edited. The two ⌘ lines without Shift are what they
always were. The two **with** Shift used to read `caret=775
selection=775..<775 “”` — identical to the `at 3@4` line above each of them,
which is what this driver prints when a keystroke does nothing at all, and
which is exactly the shape of the four lines quoted at the top of this item.

So: the caret lands on the same offset with Shift as without — 0 for up, 863
for down — and Shift decides only whether the text between there and 775 comes
with it. That is the same sentence 0494 wrote for ⇧↑ and ⇧⇟.

**Run twice, and soft wrap makes no difference to these four.** The unwrapped
run is above; the wrapped one was `diff`ed against it from `at 3@4` to the end
and the two are byte-identical. Earlier in the same run they are not — `↑` from
`0@400` is 197 wrapped and 0 unwrapped, as 0494 documented — so the comparison
is of two genuinely different runs and not of the same file twice. It could not
have come out otherwise, since `moveToDocumentEdge` is offset 0 and
`utf16Count` and never asks about a row, but the setting persists between
launches and that is exactly how a run gets read as the wrong one of the two.

## Is any other motion still missing its twin

The claim at the top of this item — that these two were the last — was made by
hand before it was filed, and an answer like that ages. It was redone
mechanically, and here is how, so the next person can run it again rather than
believe this paragraph.

**Reading the switch is not enough.** The obvious check is to list the cases,
strip `AndModifySelection`, and look for a base without a twin. Run against
`doCommand` after this change, that reports **two** gaps —
`scrollPageUpAndModifySelection:` and `scrollPageDownAndModifySelection:`. Both
are false: neither selector exists. `scrollPageUp:` and `scrollPageDown:` are
*scrolling* commands on `NSResponder`, which have no shifted form because
scrolling has no caret to drag. A rule that invents selector names by gluing a
suffix on will keep finding those two.

So the list came from AppKit instead. `NSResponder.h` in the macOS SDK declares
**22** `…AndModifySelection:` methods, and that is the whole family — a motion
that has a shifted twin has it there and nowhere else:

    H=$(xcrun --sdk macosx --show-sdk-path)/System/Library/Frameworks/AppKit.framework/Headers/NSResponder.h
    grep -o '\- *(void)[a-zA-Z]*AndModifySelection:' "$H" | sed 's/.*)//;s/:$//' | sort -u

Each of those 22 was then looked up in the `doCommand` switch
(`CodeView.swift:2085`–`2148`, 46 `#selector` cases) together with its base:

    twin                                          twin?  base?
    moveBackwardAndModifySelection                no     no
    moveDownAndModifySelection                    yes    yes
    moveForwardAndModifySelection                 no     no
    moveLeftAndModifySelection                    yes    yes
    moveParagraphBackwardAndModifySelection       no     no
    moveParagraphForwardAndModifySelection        no     no
    moveRightAndModifySelection                   yes    yes
    moveToBeginningOfDocumentAndModifySelection   yes    yes   ← this item
    moveToBeginningOfLineAndModifySelection       yes    yes
    moveToBeginningOfParagraphAndModifySelection  no     no
    moveToEndOfDocumentAndModifySelection         yes    yes   ← this item
    moveToEndOfLineAndModifySelection             yes    yes
    moveToEndOfParagraphAndModifySelection        no     no
    moveToLeftEndOfLineAndModifySelection         yes    yes
    moveToRightEndOfLineAndModifySelection        yes    yes
    moveUpAndModifySelection                      yes    yes
    moveWordBackwardAndModifySelection            yes    yes
    moveWordForwardAndModifySelection             yes    yes
    moveWordLeftAndModifySelection                yes    yes
    moveWordRightAndModifySelection               yes    yes
    pageDownAndModifySelection                    yes    yes
    pageUpAndModifySelection                      yes    yes

**Every row is `yes yes` or `no no`, and that is the answer.** Sixteen twins
are handled and all sixteen bases are handled with them. The other six are not
handled — and neither is the base of any of them, so those keys are dead in
both forms rather than half dead. A key that does nothing whether or not Shift
is held is not this bug; this bug is a key that moves and then refuses to
select, and after this change there is no such key left. The check also runs
the other way — a twin handled whose base is missing — and finds nothing.

The six with no case either way are the paragraph motions (⌃⌥↑ and the rest)
and `moveBackward:`/`moveForward:`, which are what ⌃B and ⌃F send. Those two
are worth a second look by somebody who wants them, because ⌃P and ⌃N *do*
work — they arrive as `moveUp:`/`moveDown:`, which are handled — so the emacs
bindings are half implemented. Not filed and not fixed: nobody has reported it,
it is the same "a keystroke nobody has asked about is a decision nobody has
made" that 0494 stopped at, and it is not a missing twin. Written down here
because the audit found it and a finding nobody wrote down is a finding nobody
made.

## Estimate

2026-08-16 10:04 — about an hour left

## Steps

- [x] `moveToBeginningOfDocumentAndModifySelection:` and
      `moveToEndOfDocumentAndModifySelection:` extend the selection to the edge
- [x] Watched with `--vertical-nav`, or whatever it is called by then, from the
      middle of a file: ⌘⇧↑ selects back to offset 0, ⌘⇧↓ forward to the end
- [x] Check no other motion is missing its twin, and say in here how that was
      checked rather than that it was
- [ ] Decide about the silent `default:`, and either do it or write down why not
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does — 0494 added two
      requirements about the edges of a file and this belongs beside them
