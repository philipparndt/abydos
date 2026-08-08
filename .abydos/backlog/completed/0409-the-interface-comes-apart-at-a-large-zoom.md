# 409. The interface comes apart at a large zoom

At 2× the navigator stops looking like itself: the tree's guide lines render
as stacks of thick blue dashes rather than lines, folder icons go blocky, every
name is truncated with an ellipsis several characters early, and the terminal
below is clipped mid-line. Nothing is unusable, but nothing looks made either.

Found while photographing the app at `--zoom 2.0` to look at something else,
which is worth saying: the zoom is a real setting somebody uses — ⌘+ goes to
2.0 in nine steps — and the shot was not an exotic state.

**What is scaled and what is not.** Every dimension goes through
`Theme.scaled(_:)`, which multiplies and *rounds to whole points*:

    func scaled(_ value: CGFloat) -> CGFloat { (value * scale).rounded() }

That is right for a border, which has to land on a pixel, and it is what makes
a whole interface zoom as one piece. What it does not do is change any of the
decisions taken at 1× — how much of a name fits before it is cut, how a dashed
guide's dash and gap relate to the row height, which SF Symbol weight is
chosen. Those were tuned at one size and are being asked to hold at another.

Where to look, roughly in the order the screenshot complains:

- **The guides are not guides.** The theory here was `NSOutlineView` drawing
  its own indentation marks, and it was wrong: the navigator draws no guides at
  all, and neither does AppKit. Photographed at 2× against 1×, the blue dashes
  are the *markdown icon*. `text.alignleft` is four lines of text at 13pt and
  four thick bars at 26, and a folder of `.md` files — the backlog, which is
  what was on screen — is a column of those running down the side of the tree.
  Blue is not a palette colour because it is not from the palette: `FileIcon`
  carries its own `0x4C7EE0`. So this bullet and the one below are the same
  fault, and the weight fixes both.
- **The truncation is fixed.** It was neither the font nor the padding: an
  outline column left to itself stays as wide as the widest name it has been
  given, so the cells were narrower than the pane and every measurement against
  them was too. The column follows the view's width now, and names truncate at
  the pane's edge rather than well inside it. The same fault was cutting the
  rename field to a third of the row.
- **The icons are fixed.** `Theme.symbol(_:size:color:weight:)` derives the
  weight it draws at from the size it was given: a notch lighter per √2 above
  16pt, which is the largest anything is asked for at 1×, so nothing at a
  design size moves and 1× is exactly what it was. `FileIcon` built its own
  configuration at a fixed `.regular` and now goes through the same call.

What is left of the opening paragraph is the terminal clipped mid-line, which
is not in the list below and was not fixed here: at 2× a full terminal shows a
part-row against the top of the viewport, because the height is not a whole
number of rows. Its own thing.

**Worth deciding first:** whether 2× is meant to be the same interface twice
the size, or a different interface for the same person at a distance. The
presentation zoom exists for a room, and a room does not want the same
information density made bigger — it wants less of it, larger. If the answer is
the first, this is a set of small fixes; if the second, it is a different task
with layout decisions in it.

## Decided

**The same interface, bigger.** A large zoom is a scaling bug, not a different
design — the room version is what `presentationScale` is for, and it stays a
separate question.

So the fixes are small and local: measure truncation with the scaled font,
derive a symbol's weight from its scaled size rather than a fixed one, and find
whoever draws the blue dashes — most likely `NSOutlineView`'s own indentation
marks, appearing because the row height has drifted from what it expects, in
which case the answer is to draw the guides ourselves as the editor already
does. All of it is checkable with the screenshot harness at `--zoom 2.0`.

---

Its number is where it sits in the queue, not what it is worth doing next.
