# 494. ⇧↑ on the first line and ⇧↓ on the last select to the edge of the file

> in the editor, when being on the first line, it shall be possible to press
> "shift + up" and select the line to the beginning. On the last line the same
> with "shift + down" (select till the end). Currently this does not work, as
> there is no line to go up or down for the cursor.

The diagnosis in the report is the code. `moveVertically`
(`CodeView.swift:2234`) works out the visual line to land on, clamps it to the
file, and then:

    let targetVisual = max(0, min(visibleLineCount - 1, visual + delta))
    guard targetVisual != visual else { return }

On the first line the clamp gives back the line the caret is already on, and
the guard turns the keystroke into nothing at all. Every other text view on
this machine — TextEdit, Xcode, Notes — takes the caret to the start of the
file instead, and takes the selection with it when Shift is down.

On the first line the start of the line and the start of the file are the same
offset, and on the last line the end of the line and the end of the file are
the same offset, so there is nothing to choose between those two readings of
the report.

## Worth deciding

- **Whether the bare arrow does it too.** ↑ with no Shift on the first line is
  the same keystroke through the same guard, and every Cocoa text view moves
  the caret to offset 0. Doing it only for Shift means writing an extra
  condition to keep ↑ doing nothing, which is harder to defend than the
  behaviour somebody's fingers already have.
- **Page Up and Page Down** come through `movePage` into the same function, so
  they get whatever is decided here. That is also what Cocoa does.
- **The remembered column.** A run of ups and downs returns to the column it
  started from (`desiredColumnX`). Jumping to the edge of the file should not
  throw that away, or ⇧↓ to the end and then ↑ comes back to the wrong place.

## Steps

- [ ] `moveVertically` at the top or bottom goes to the edge of the file
      instead of returning
- [ ] It extends the selection when Shift is held, and moves the caret when it
      is not
- [ ] The remembered column survives the jump
- [ ] A test for the motion that does not need a window, if the arithmetic can
      be got at from `AbydosKit`
- [ ] A driver so the keys can be watched from outside the app, as `--word-nav`
      does for ⌥←/⌥→
- [ ] Watched: ⇧↑ on the first line, ⇧↓ on the last, and both in a wrapped file
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does
