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

## Worth deciding

- **Whether logical order should simply be visual order here.** Mapping
  `moveForward:` onto the same code as `moveRight:` is one line each and right
  for every file this editor opens. It is *wrong* for right-to-left text, where
  forward is left — so the honest thing is to decide it and write down that it
  was decided, rather than to alias the two and leave somebody to discover the
  difference in an Arabic string literal. Nothing else in this editor handles
  RTL specially, so the answer is probably "the same, and said out loud".
- **Four selectors or two.** `moveForwardAndModifySelection:` and
  `moveBackwardAndModifySelection:` (`NSResponder.h:170-171`) are ⇧⌃F and ⇧⌃B.
  Doing the bare pair alone leaves the emacs motions half-working in the other
  direction, which is the shape 0495 exists to stop.
- **The rest of the emacs family is a separate question.** ⌃A, ⌃E, ⌃D and ⌃K
  are their own selectors and their own decisions; this item is the pair that
  was reported. Widening it is how it stops being reviewable.

## Ruled out

- **Anything that touches ⌃B outside the editor.** ⌃B is tmux's prefix key, and
  this app has terminal panes. This is `CodeView.doCommand` and nothing else —
  no global shortcut, no menu item, nothing that could take ⌃B before a
  terminal sees it.

## Steps

- [ ] `moveForward:` and `moveBackward:` move the caret one character
- [ ] `moveForwardAndModifySelection:` and `moveBackwardAndModifySelection:`
      extend the selection the same way
- [ ] Decide about logical against visual order, and write the answer down
      whichever way it goes
- [ ] Watched from outside the app: ⌃B, ⌃F, ⇧⌃B and ⇧⌃F, with the caret
      mid-line, and ⌃B at the start of a line to see what it does at an edge
- [ ] `make test` and `make warnings` are clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does, beside what 0494 and
      0495 put there about the arrows
