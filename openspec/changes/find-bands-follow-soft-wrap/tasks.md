## 1. Read before writing

- [ ] 1.1 Read `RevealScroll`, added by 0533 with the range/point distinction in
      mind, and say whether it already has the shape this needs.
- [ ] 1.2 Decide: reuse `point(forUTF16:)` through a range-shaped sibling, or teach
      the highlight path the wrap layout. Write down which and what killed the other.
- [ ] 1.3 Check whether folding has the same fault — `searchHighlights` takes
      `docLine` from the caller — and record the answer before deciding scope.

## 2. The arithmetic

- [ ] 2.1 `searchHighlights(docLine:rect:)` returns one rect per match per visual row
      it touches, rather than one rect per match.
- [ ] 2.2 Positions are measured along the visual row being painted, not along a
      `CTLine` built for the whole document line.
- [ ] 2.3 Pull the offset-to-x step out far enough to assert without a window, the
      way 0536 did for the order — without putting view code in `AbydosKit`.

## 3. Tests

- [ ] 3.1 A match on the second visual row of a wrapped line is at the right x.
- [ ] 3.2 A match spanning a wrap boundary yields two rects, each bounded by its row.
- [ ] 3.3 A match spanning three rows bands the intervening row across its text.
- [ ] 3.4 The caret's position and the band's left edge agree for the same offset —
      the test that stops the two answers drifting apart again.
- [ ] 3.5 An unwrapped line is unchanged.

## 4. Watched

- [ ] 4.1 Screenshots on a wrapped line with several matches, before and after, next
      to `images/wrapped-line-defect.png` from 0536.
- [ ] 4.2 The same with a fold above the matched line.

## 5. Finish

- [ ] 5.1 `make test` and `make warnings` both clean.
- [ ] 5.2 Folding either fixed with this or named here as unaffected — not left
      unexamined.
- [ ] 5.3 Write down what was ruled out on the way.
- [ ] 5.4 `.abydos/backlog/spec/search.md` says what the project now does.
