# 497. ⌃B and ⌃F do nothing while ⌃P and ⌃N work

macOS has carried the emacs motions since NeXT, and they work in every standard
text view — TextEdit, Mail, Notes, Xcode, any `NSTextField`. ⌃B goes back a
character, ⌃F forward one, ⌃P up a line, ⌃N down one. Here the vertical half
works and the horizontal half does nothing at all.

`NSResponder.h:152-155` is the whole of why:

    - (void)moveForward:(id)sender;    // ⌃F
    - (void)moveRight:(id)sender;      // →
    - (void)moveBackward:(id)sender;   // ⌃B
    - (void)moveLeft:(id)sender;       // ←

Four methods, not two. `moveForward:` is not `moveRight:` — the pair is
*logical* order against *visual* order, and they part company in right-to-left
text. `CodeView.doCommand` answers to the visual pair and not the logical one,
so ⌃B and ⌃F fall through `default:` and are dropped. ⌃P and ⌃N survive because
AppKit sends them as plain `moveUp:` and `moveDown:`, which are handled; there
is no separate logical selector vertically for them to fall through.

**This is not a gap 0495's audit missed.** That one paired every
`…AndModifySelection:` with its base and found every row yes/yes or no/no. Both
halves of this pair are unhandled, so its rows were honest — a whole motion is
absent rather than half of one, which is a different question and this is it.

Found while answering "what do ⌃B and ⌃F usually do", after 0495 recorded them
in passing.

## Worth deciding — decided

**The two selectors share a case, and the reason is not the one this item
expected.** `moveForward:` goes to the same code as `moveRight:`, and
`moveBackward:` to the same as `moveLeft:`. What the item guessed would be a
concession — aliasing logical order onto visual order and hoping RTL never
turns up — is the wrong way round once you read what the code on the other end
of `moveRight:` actually does:

    private func moveHorizontally(_ delta: Int, extending: Bool) {
        …
        var offset = caret + delta

`caret + delta` is an offset into the document. That is **logical order
already**. There is no visual-order motion in this editor to alias anything
onto: `moveRight:` has been pointed at the logical one since it was written,
and in right-to-left text it is → that goes the wrong way, both before this
change and after it. ⌃F is the selector that is *correctly* named for what
these four cases do.

So the decision, said out loud as the item asked: **this editor has one
horizontal motion and it is the logical one.** ⌃F and → both step one character
forward through the document; ⌃B and ← both step one back. In an RTL line that
makes ⌃F right and → wrong, and → is exactly as wrong as it was yesterday.

Three things checked rather than assumed before writing that:

- **Nothing in this editor does bidi.** `git ls-files '*.swift' | xargs grep -l`
  for `bidi`, `rightToLeft`, `WritingDirection`, `kCTRunStatus` matches **no
  Swift file in the repository**. The one place the two orders could differ is
  drawing — a line goes to `CTLineCreateWithAttributedString`
  (`CodeView.swift:648`), and CoreText reorders bidi runs when it lays one out
  — so an RTL line would be *drawn* reordered while every offset around it
  stayed logical. That is a pre-existing gap between what is drawn and what the
  arrows do, it is what RTL support would have to close, and it is not this
  item.
- **The same switch has paired the same two orders for as long as it has had
  word motion.** `moveWordLeft:`/`moveWordBackward:` share a case and
  `moveWordRight:`/`moveWordForward:` share the other one
  (`CodeView.swift:2125`). ⌥← and ⌥→ have therefore always answered to both
  orders. Doing anything else for the character pair would have made the two
  neighbouring pairs disagree about a question neither of them can answer.
- **The pairing is not a guess about what ⌃F sends.** macOS says so:
  `/System/Library/Frameworks/AppKit.framework/Resources/StandardKeyBinding.dict`
  binds `^f` → `moveForward:`, `^b` → `moveBackward:`, `^F` →
  `moveForwardAndModifySelection:`, `^B` → `moveBackwardAndModifySelection:`.

**Four selectors, not two.** The `AndModifySelection:` twins are in, in the
same commit as the bare pair. 0495's audit already recorded both rows as
no/no — a whole motion missing rather than half of one — and doing the bare
pair alone would have converted it into exactly the half-a-motion shape 0495
exists to stop.

**The rest of the emacs family stays out, and is now filed rather than
guessed at.** See "The rest of the family" below: ⌃D already works, and ⌃A, ⌃E
and ⌃K are dead for a different reason than this item's, which is why they are
0498 and not more lines here.

## The rest of the family — pressed once, then filed as 0498

The item says ⌃A, ⌃E, ⌃D and ⌃K are their own decisions, and they are. What
they are not is a guess: the driver was given a probe with all four in it, run
once, and the probe taken out again — the same move 0494 made with ⌘⇧↑ and 0495
made with the wrap comparison.

    EMACS: ⌃A          caret=50 selection=50..<50 “”
    EMACS: ⌃E          caret=50 selection=50..<50 “”
    EMACS: ⌃D          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃D third ine of the file
    EMACS: ⌃K          caret=50 selection=50..<50 “”
    EMACS: PROBE after ⌃K third ine of the file

**⌃D already works** — the caret staying at 50 is right for a forward delete,
and the `l` of `third line` is gone. **⌃A, ⌃E and ⌃K do nothing**, and reading
the switch would have said the opposite: `moveToBeginningOfLine:`,
`moveToEndOfLine:` and `deleteToEndOfLine:` all have cases. They are not the
selectors those keys send. `StandardKeyBinding.dict` binds `^a`, `^e` and `^k`
to the **paragraph** selectors, which have no case — the same six rows 0495's
audit listed as handled in neither form.

That is a different bug from this one with a real question inside it (what a
paragraph is in a file of source), so it is **0498** in `open/`, and four
keystrokes stayed out of this item.

## Ruled out

- **Anything that touches ⌃B outside the editor.** ⌃B is tmux's prefix key, and
  this app has terminal panes. This is `CodeView.doCommand` and nothing else —
  no global shortcut, no menu item, nothing that could take ⌃B before a
  terminal sees it.

## Estimate

2026-08-16 11:50 — about an hour left

## Steps

- [x] `moveForward:` and `moveBackward:` move the caret one character
- [x] `moveForwardAndModifySelection:` and `moveBackwardAndModifySelection:`
      extend the selection the same way
- [x] Decide about logical against visual order, and write the answer down
      whichever way it goes
- [x] The rest of the emacs family: press it once and file what is missing,
      rather than guess which of ⌃A, ⌃E, ⌃D and ⌃K are worth an item

      Added while doing the work. The item said the rest of the family was a
      separate decision and left it at that; it costs one driver run to make
      that decision on evidence instead. ⌃D works, ⌃A, ⌃E and ⌃K do not, and
      **0498** says why — they are the paragraph selectors, not the line ones.
- [ ] A driver that can press a letter key with a modifier at all —
      `simulateArrow` knew the four arrows and the two page keys and nothing
      else, so there was no way to press ⌃B through `keyDown`

      Added while doing the work: the item assumed 0494's driver could be
      extended, and it could not reach these keys without being widened first.
- [ ] Watched from outside the app: ⌃B, ⌃F, ⇧⌃B and ⇧⌃F, with the caret
      mid-line, and ⌃B at the start of a line to see what it does at an edge
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does, beside what 0494 and
      0495 put there about the arrows
