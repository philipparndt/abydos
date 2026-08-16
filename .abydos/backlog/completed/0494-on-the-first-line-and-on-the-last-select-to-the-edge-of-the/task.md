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

## The wrapped line: this fixed a second bug, it did not avoid one

`wrapSegmentForOffset` already existed at `CodeView.swift:1385` and
`moveVertically` was not using it: it asked `folding.visualLine(forDocumentLine:)`
for the caret's row, which with soft wrap on is not a row at all — it counts
lines, and a wrapped line is several rows. Whether this change **fixed** a
second bug or merely **avoided introducing** one are two different sentences
and only one of them can go in the item, so it was answered by running it and
not by reading it: the pre-change `moveVertically` was put back into the
working tree, built, and driven against the same file with `--wrap`.

**It was already broken, and worse than what was reported.** The file is seven
lines, the first of them 723 characters, which the window wrapped into four
rows of about 203:

    VERT: word wrap is on
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇧↑          caret=8 selection=8..<8 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=812 selection=812..<834 “h line…”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↑           caret=400 selection=400..<400 “”
    VERT: ↑ again     caret=400 selection=400..<400 “”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↓           caret=400 selection=400..<400 “”
    VERT: ↓ again     caret=400 selection=400..<400 “”

Two things there that nobody had reported. ↑ and ↓ **partway along a wrapped
line did nothing at all** — 400, 400, 400 — because the row the motion started
from was the line's number rather than the caret's row, so the row it asked for
was the row the caret was already on and the offset came back the same. And ⇧↓
on the last line did not merely fail: it put the caret on **line 4**, two lines
*up* the file, and selected backwards to it. Row 7 of a document whose first
line owns rows 0 to 3 is the fifth line, and asking for it by line number is
how a keystroke labelled "down" moves up.

Unwrapped, the same control run says exactly what the report says and nothing
more — all four keystrokes dead at the edges, ordinary ↑ and ↓ fine:

    VERT: word wrap is off
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇧↑          caret=8 selection=8..<8 “”
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ↑           caret=8 selection=8..<8 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=834 selection=834..<834 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ↓           caret=834 selection=834..<834 “”

So the sentence is "this fixed a second bug". It is not in the report because
soft wrap is off by default and whoever had it on had a broken ↓ everywhere in
the file rather than only at its edges.

## Watched in the app

`--vertical-nav`, against a seven-line scratch file whose first line is 723
characters and which deliberately has **no trailing newline**, so that the last
line has text on it and ⇧↓ there has something to select. Line 6 starts at 830
and the file ends at 863.

    $ build/Abydos.app/Contents/MacOS/Abydos --open …/vert --file …/vertical.txt --vertical-nav

    VERT: word wrap is off
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇧↑          caret=0 selection=0..<8 “one word”
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ↑           caret=0 selection=0..<0 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ↓           caret=863 selection=863..<863 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: then ↑      caret=823 selection=823..<823 “”
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇞           caret=0 selection=0..<0 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧⇟          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↑           caret=0 selection=0..<0 “”
    VERT: ↑ again     caret=0 selection=0..<0 “”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↓           caret=742 selection=742..<742 “”
    VERT: ↓ again     caret=765 selection=765..<765 “”

⇧↑ takes "one word" with it; the bare ↑ goes to the same place and leaves the
selection empty; ⇧↓ selects the rest of the last line and ↓ moves to its end.
`then ↑` is the column memory: from the end of the file (column 33) it comes
back to 823, which is column 4 of the line above — the column the run started
at — and not to that line's end. The two ↓ at the bottom land on 742 and 765,
the ends of two short lines, because the remembered column is past them.

The same run with `--wrap`, where the rows are segments of line 0:

    $ … --wrap --vertical-nav

    VERT: word wrap is on
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇧↑          caret=0 selection=0..<8 “one word”
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ↑           caret=0 selection=0..<0 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ↓           caret=863 selection=863..<863 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧↓          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: then ↑      caret=823 selection=823..<823 “”
    VERT: at 0@8      caret=8 selection=8..<8 “”
    VERT: ⇞           caret=0 selection=0..<0 “”
    VERT: at last@4   caret=834 selection=834..<834 “”
    VERT: ⇧⇟          caret=863 selection=834..<863 “nth and last line of the file”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↑           caret=197 selection=197..<197 “”
    VERT: ↑ again     caret=0 selection=0..<0 “”
    VERT: at 0@400    caret=400 selection=400..<400 “”
    VERT: ↓           caret=603 selection=603..<603 “”
    VERT: ↓ again     caret=723 selection=723..<723 “”

The edges answer the same wrapped as unwrapped, and the middle of the wrapped
line now moves a row at a time: 400 → 197 is up one row at the same column, and
only the ↑ after that runs out of rows and goes to offset 0. Downwards it is
400 → 603 → 723, the last of those being the end of line 0, because the row
below is shorter than the column being kept.

## Found and ruled out on the way

- **`--word-nav` prints nothing when it is redirected, and always did.** stdout
  to a file is block buffered, a driver run ends by killing the app, and the
  buffer dies with the signal. Twenty minutes went into "the driver is not
  being reached" before it turned out to be the six lines it had already
  printed. Both drivers flush per line now. Anything written next in this
  pattern should.
- **⇧⇞ and ⇧⇟ reached the editor as nothing at all.** Their own selectors,
  `pageUpAndModifySelection:` and `pageDownAndModifySelection:`, which
  `doCommand` did not have a case for. Fixed here, since this item's decision is
  that Shift decides whether the selection comes along.
- **⌘⇧↑ and ⌘⇧↓ are dead in the same way, and are not fixed here.** Watched,
  from the same driver, before the probe was taken out again:

      VERT: at 0@8      caret=8 selection=8..<8 “”
      VERT: ⌘⇧↑         caret=8 selection=8..<8 “”
      VERT: at last@4   caret=834 selection=834..<834 “”
      VERT: ⌘⇧↓         caret=834 selection=834..<834 “”

  `moveToBeginningOfDocument:` and `moveToEndOfDocument:` are handled and their
  `AndModifySelection` twins are not, so ⌘↑ and ⌘↓ move and the shifted pair do
  nothing. It is two lines and the same shape as the page keys, and it is left
  alone because it is a keystroke nobody has asked about and the reporter
  decided the arrows, not the whole family. Worth filing on its own.
- **A programmatic `setCaret` does not forget the remembered column**, only a
  click and the horizontal motions do. So after ⌘L or a jump to a definition,
  the first ↑ or ↓ returns to a column from before the jump. Pre-existing, not
  this item, and not fixed — but it is why the driver's own caret placement
  clears it, or every report after the first would have carried the previous
  test's column.
- **The end of a file whose tail is folded.** ↓ on the last visible row goes to
  the real end of the document, and `setCaret` reveals a collapsed region the
  caret lands in, so the fold opens. Considered stopping at the end of the last
  *visible* line instead and did not: the reporter asked for the end of the
  file, a selection that stops short of it is the surprising one, and going to
  a folded offset is what ⌘L and go-to-definition already do.
- **A file that ends with a newline has an empty last line**, so ⇧↓ there is
  already at the end of the document and selects nothing. That is not a case in
  the code — the last line is the empty one and the caret is already on the last
  row — but it is why the scratch file used for watching has no trailing
  newline. With one, the interesting keystroke is on the second-to-last line.
- **Shift-only was not built.** Keeping the bare arrow dead needs a condition
  written specially to do nothing, and the decision above went the other way.

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
- [x] Watched: ⇧↑ on the first line, ⇧↓ on the last, the bare ↑ and ↓ in the
      same two places, and all of it again in a wrapped file
- [x] Answered by running it: was ↑/↓ inside a soft-wrapped line broken before
      this change, or only nearly
- [x] `make test` and `make warnings` both clean
- [x] Write down here what was ruled out on the way
- [x] `spec/editor.md` says what the project now does, for the bare arrow as
      well as for the shifted one
