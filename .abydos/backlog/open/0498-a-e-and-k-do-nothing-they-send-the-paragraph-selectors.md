# 498. ⌃A, ⌃E and ⌃K do nothing: they send the paragraph selectors

0497 gave ⌃B and ⌃F their cases and left the rest of the emacs family alone,
because a keystroke nobody has asked about is a decision nobody has made. On
the way it pressed the rest of the family through the same driver, and the
answer is not the one you would guess from the selector names:

    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃A          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃E          caret=50 selection=50..<50 “”
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃D          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃D third ine of the file
    EMACS: at 2@6      caret=50 selection=50..<50 “”
    EMACS: ⌃K          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃K third ine of the file

**⌃D works** — the caret does not move, which is right, and the `l` at offset
50 is gone from `third line`. **⌃A, ⌃E and ⌃K do nothing at all**, and ⌃K
leaves the line exactly as ⌃D left it.

`CodeView.doCommand` handles `moveToBeginningOfLine:`, `moveToEndOfLine:` and
`deleteToEndOfLine:`, so reading the switch says these three should work. They
do not, because those are not the selectors those keys send. macOS's own table
is the answer —
`/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`:

    ^a  moveToBeginningOfParagraph:
    ^e  moveToEndOfParagraph:
    ^k  deleteToEndOfParagraph:
    ^d  deleteForward:              ← the one that is handled, and works

So this is the **paragraph** family and not the line family. 0495's audit
already listed `moveToBeginningOfParagraphAndModifySelection` and
`moveToEndOfParagraphAndModifySelection` as handled-neither-way, along with
`moveParagraphForwardAndModifySelection` and its backward twin, which are ⌃⌥↑
and ⌃⌥↓ and are dead for the same reason.

**Worth knowing before starting:** in a code editor a paragraph is not a
paragraph. Cocoa means "up to the next hard line break", which in a file of
source is a line — so `moveToBeginningOfParagraph:` can honestly go to the same
code as `moveToBeginningOfLine:` here, exactly as 0497 sent `moveForward:` to
the same code as `moveRight:`. That is the decision this item is really about,
and it wants writing down rather than aliasing quietly. What it is *not* is the
soft-wrap question: whether ⌃A on a wrapped row goes to the start of the row or
the start of the line is a separate answer, and `moveToLineEdge` already has
one that this item should not change by accident.

## Ruled out

- **Doing it inside 0497.** Its reported pair is `moveForward:`/`moveBackward:`
  — logical against visual order, one decision. This is a different family with
  a different question in it (what a paragraph means in code), and ⌃K deletes,
  which nothing in 0497 did. Bundling them would have made one item nobody
  could review.

## Steps

- [ ] Decide what a paragraph is in this editor, and write the answer down
- [ ] `moveToBeginningOfParagraph:` and `moveToEndOfParagraph:` move the caret,
      and their `AndModifySelection:` twins take the selection with them
- [ ] `deleteToEndOfParagraph:` deletes, so ⌃K does something
- [ ] Decide about ⌃⌥↑ and ⌃⌥↓ — `moveParagraphForward:`/`moveParagraphBackward:`
      are the same family and unhandled, and either belong here or are said not to
- [ ] Watched from outside the app with `--emacs-nav`, which already knows the
      key codes for all of these letters
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
