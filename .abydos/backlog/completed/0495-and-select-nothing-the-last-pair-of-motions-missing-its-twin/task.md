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

## Worth deciding — decided, and not here

- **Whether `default:` should be as quiet as it is.** Every one of these three
  was invisible for the same reason: an unhandled selector falls through a
  `default: break` whose comment says staying silent is right, and it *is*
  right — AppKit sends `noop:` and much else. But it is also why a missing
  motion looks exactly like a key that does nothing, three times now. A debug
  build that logged unhandled `move*`/`select*` selectors once each would have
  caught all three in one session, and would say nothing in release. Worth
  weighing against the noise before writing it.

  **Weighed, and it is worth doing — as
  [0496](../../open/0496-a-debug-build-says-which-move-and-select-selectors-nothing.md),
  not as part of this.** The reasoning, in three parts:

  *The noise is not a worry, and that is a number and not an opinion.* The
  macOS 27.0 SDK's `NSResponder.h` declares 43 methods beginning `move` or
  `select`; `doCommand` handles 29. So a once-each log has a **ceiling of 14
  lines for the entire life of a debug build**, and only for keys somebody
  actually pressed. The ceiling is the size of a family AppKit fixes at compile
  time — it does not grow with how long the app runs or how much is typed,
  which is exactly what makes it different from logging `default:` whole, where
  `noop:` alone would drown it.

  *The claim in the paragraph above is slightly too strong, and it is worth
  saying so.* Nothing prints until the key is pressed, so this does not find a
  bug nobody triggers. What it does is collapse the second half of the hunt:
  "this key does nothing, why?" becomes "this key does nothing, and here is the
  selector nobody handled". On 0494 that second half was a person reading the
  switch, and it was not quick.

  *What makes it worth more than that sounds: the drivers press keys.*
  `--vertical-nav` and `--word-nav` already sweep a corner of the keyboard on
  purpose, so a debug driver run would print the unhandled selectors beside its
  own report — turning a diagnosis aid into something closer to a detector, for
  free, in a run that an editor item does anyway. 0494's session pressed ⇧⇞,
  ⇧⇟, ⌘⇧↑ and ⌘⇧↓ through the driver, so all four would have named themselves
  in that one run.

  **Not implemented here.** It is a change to how the editor reports on itself,
  not to what a keystroke does, and it wants deciding on its own terms — where
  it logs, whether the project has a debug channel to use, how it is shown to
  be silent in release. Bundling it into a two-selector fix would be exactly
  the widening this item was filed to avoid.

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

## Found and ruled out on the way

- **The two lines turned into four, and that was worth it.** The item says two
  cases, and two cases is what it needs. But the plain pair were written inline
  and differently from each other — one a literal `setCaret(0, …)`, the other
  `setCaret(document?.rope.utf16Count ?? 0, …)` — and adding two shifted copies
  beside them would have made four spellings of one motion in six lines. They
  all go through one `moveToDocumentEdge(start:extending:)` now. Checked to be
  behaviour-preserving for the unshifted pair and not merely tidier: the old
  `?? 0` could only fire with no document, and `setCaret` already returns early
  in that case, so the fallback was unreachable.

- **The remembered column is deliberately *not* cleared, and that is not an
  oversight.** `moveHorizontally` and `moveToLineEdge` both begin
  `desiredColumnX = nil`; `moveToDocumentEdge` does not. Left that way because
  the old inline cases did not clear it either, so the unshifted keys behave
  exactly as before — and because 0494's rule is that a jump to the end of the
  file is part of a run of ups and downs and the column survives it. Clearing
  it here would have been an unasked-for change to ⌘↑, smuggled in under a fix
  for ⌘⇧↑.

- **No unit test, and there is nowhere honest to put one.** 0494 could write
  `VerticalMotionTests` because it had arithmetic to test — `VerticalMotion` is
  a pure type in `AbydosKit`. This item has no arithmetic: it is a `switch` case
  routing a selector to offset 0 or to `utf16Count`. There is one test target,
  `AbydosKitTests`, and `CodeView` is in `AbydosApp` and needs a window, so
  there is no existing seam to test through. A new pure type whose only job is
  to map two selector names to two booleans would be a test of the test. The
  driver run above is the check, which is why the step asked for it.

- **`scrollPageUp:` and `scrollPageDown:` are not motions missing a twin**,
  though the obvious way of auditing says they are. See the audit section: they
  are scrolling commands, AppKit declares no shifted form of either, and any
  check that builds selector names by gluing `AndModifySelection` onto the ones
  we handle will report them forever. This cost a few minutes and is the reason
  the audit is written against `NSResponder.h` instead.

- **⌃B and ⌃F do nothing, while ⌃P and ⌃N work.** Turned up by the audit, not
  reported by anybody. It is not this bug — both halves are dead rather than
  one — and it is not fixed here for the same reason 0494 did not fix these
  two. Recorded at the bottom of 0496, which is where somebody looking at
  unhandled selectors will be.

- **The soft wrap setting persists between launches, and bit again.** The first
  driver run came up `word wrap is on` without being asked, because 0494's
  session left it that way. Harmless for this item — the ⌘ block is
  byte-identical either way, `diff`ed rather than eyeballed — but it is the
  second item in a row where the first run was not the mode the runner
  expected. The driver printing which mode it is in is what made it a
  non-event.

## Steps

- [x] `moveToBeginningOfDocumentAndModifySelection:` and
      `moveToEndOfDocumentAndModifySelection:` extend the selection to the edge
- [x] Watched with `--vertical-nav`, or whatever it is called by then, from the
      middle of a file: ⌘⇧↑ selects back to offset 0, ⌘⇧↓ forward to the end
- [x] Check no other motion is missing its twin, and say in here how that was
      checked rather than that it was
- [x] Decide about the silent `default:`, and either do it or write down why not

      Ticked for the second of those two, not the first: **the `default:` in
      `CodeView.swift` is unchanged by this item.** The deciding is the step and
      it is finished — the weighing is under "Worth deciding" above, and it
      concluded the logging *is* worth having, so it is filed as **0496** and
      left in `open/` for somebody to agree to. Why not here: it changes how the
      editor reports on itself rather than what a keystroke does, and this item
      is two selectors. Why worth doing at all: the noise ceiling is 14 lines for
      the life of a debug build, counted from `NSResponder.h` rather than
      guessed, and the drivers already press the keys that would print them.
- [x] `make test` and `make warnings` both clean

      Added while doing the work rather than written down at the start: every
      item does it and this one did not say so. 2610 tests in 365 suites
      passed; `make warnings` says no warnings in this repository's Swift, with
      only the four vendored tree-sitter C warnings it always reports.
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does — 0494 added two
      requirements about the edges of a file and this belongs beside them

      One `MODIFIED` of "Shift takes the selection to the edge with it", and no
      third `ADDED`. 0494's other requirement is about a vertical key *running
      out of rows*, which is not what ⌘↑ does — it jumps from wherever the
      caret is and never asks about a row — so ⌘⇧↑ does not belong under it.
      The requirement it does go under states this item's rule word for word:
      Shift decides only whether the selection comes along. A third requirement
      would be that sentence again with two more keys in it, and two copies of
      one rule are two things that eventually disagree.
