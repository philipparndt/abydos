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

## Worth deciding — decided

**The bare arrow does it too.** Decided by Philipp, who reported it, on
2026-08-16: ↑ on the first line takes the caret to the start of the file and ↓
on the last takes it to the end, whether or not Shift is held. Shift only
decides whether the selection comes along. Every Cocoa text view on this
machine does that, and doing it only for Shift would have meant writing an
extra condition whose whole purpose is to keep ↑ dead — harder to defend than
the behaviour somebody's fingers already have.

**Page Up and Page Down get it too**, because `movePage` computes a screenful
and calls the same function; a page that overshoots the top now lands at offset
zero rather than at column whatever of line one. That is also what Cocoa does,
and it was not worth an exception.

**The remembered column survives the jump.** A run of ups and downs returns to
the column it started from (`desiredColumnX`), and the jumps to either end are
part of the run: ⇧↓ to the end of the file and then ↑ comes back to the column
the run started at, not to whatever column the last line happens to end at.

## A question this had to settle

`wrapSegmentForOffset` already existed at `CodeView.swift:1385` and
`moveVertically` was not using it: it asked `folding.visualLine(forDocumentLine:)`
for the caret's row, which with soft wrap on is not a row at all. So ↑ and ↓
inside a wrapped file may have been broken before any of this. Whether this
change **fixed** a second bug or merely **avoided introducing** one is a
different sentence to write in the spec and in this item, and only one of them
is true. It is answered below, by running it.

## Estimate

2026-08-16 11:40 — about an hour and a half left

## Steps

- [x] `moveVertically` at the top or bottom goes to the edge of the file
      instead of returning
- [x] It extends the selection when Shift is held, and moves the caret when it
      is not
- [x] The remembered column survives the jump
- [x] A test for the motion that does not need a window, if the arithmetic can
      be got at from `AbydosKit`
- [x] A driver so the keys can be watched from outside the app, as `--word-nav`
      does for ⌥←/⌥→
- [x] ⇧⇞ and ⇧⇟ arrive at the editor at all — found by watching them, and not
      in the report
- [ ] Watched: ⇧↑ on the first line, ⇧↓ on the last, the bare ↑ and ↓ in the
      same two places, and all of it again in a wrapped file
- [ ] Answered by running it: was ↑/↓ inside a soft-wrapped line broken before
      this change, or only nearly
- [ ] `make test` and `make warnings` both clean
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what the project now does, for the bare arrow as
      well as for the shifted one
