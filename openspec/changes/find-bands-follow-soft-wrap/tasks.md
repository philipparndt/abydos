## 1. Read before writing

- [x] 1.1 Read `RevealScroll`, added by 0533 with the range/point distinction in
      mind, and say whether it already has the shape this needs.
- [x] 1.2 Decide: reuse `point(forUTF16:)` through a range-shaped sibling, or teach
      the highlight path the wrap layout. Write down which and what killed the other.
- [x] 1.3 Check whether folding has the same fault — `searchHighlights` takes
      `docLine` from the caller — and record the answer before deciding scope.

## 2. The arithmetic

- [x] 2.1 `searchHighlights(docLine:rect:)` returns one rect per match per visual row
      it touches, rather than one rect per match.
- [x] 2.2 Positions are measured along the visual row being painted, not along a
      `CTLine` built for the whole document line.
- [x] 2.3 Pull the offset-to-x step out far enough to assert without a window, the
      way 0536 did for the order — without putting view code in `AbydosKit`.

## 3. Tests

- [x] 3.1 A match on the second visual row of a wrapped line is at the right x.
- [x] 3.2 A match spanning a wrap boundary yields two rects, each bounded by its row.
- [x] 3.3 A match spanning three rows bands the intervening row across its text.
- [x] 3.4 The caret's position and the band's left edge agree for the same offset —
      the test that stops the two answers drifting apart again.
- [x] 3.5 An unwrapped line is unchanged.

## 4. Watched

- [x] 4.1 Screenshots on a wrapped line with several matches, before and after, next
      to `images/wrapped-line-defect.png` from 0536.
- [x] 4.2 The same with a fold above the matched line.

## 5. Finish

- [x] 5.1 `make test` and `make warnings` both clean.
- [x] 5.2 Folding either fixed with this or named here as unaffected — not left
      unexamined.
- [x] 5.3 Write down what was ruled out on the way.
- [x] 5.4 `.abydos/backlog/spec/search.md` says what the project now does.

## 6. What the reading settled

- [x] 6.1 **`RevealScroll` is the precedent, not the component** (1.1). It answers
      where a pane must scroll to, not where a range is drawn; what it lends is
      the shape — the arithmetic in `AbydosKit` where it can be asked without a
      window, which is what let this be tested at all.
- [x] 6.2 **Neither reuse nor re-teach: the same question, asked twice** (1.2).
      `point(forUTF16:)` answers for one offset and maps it to *its* row, which a
      band cannot use — a band needs the piece that falls on the row being
      painted. So the highlight path slices with `WrapLayout.segmentRange`, the
      call the caret already makes, and `bandRange` clips to it. The test that
      the two agree offset for offset is what stops them drifting again.
- [x] 6.3 **Folding was already right** (1.3, 5.2). `docLine` and the segment both
      come from the fold-aware mapping in the draw loop, so the fold case needed
      no code — and was driven anyway, with thirteen lines folded away above the
      matches.
- [x] 6.4 A driver verb was needed to see any of it: `--editor-shot` captures the
      editor view rather than the window. The window capture photographed the
      bottom panel, which is how a picture of "no code at all" nearly became this
      change's evidence.
