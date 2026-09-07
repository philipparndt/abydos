## 1. The cuts

- [x] 1.1 `WrapLayout.rowStarts(in:columns:tabWidth:)` — one walk, cutting
  after the last whitespace that follows a word, at the edge when there is
  none, never at leading indentation; `segmentRange`, `segment(forOffset:)`
  and `rowCount` read it.
- [x] 1.2 `WrapAtWordsTests` in `WrapLayoutTests.swift`: the sentence, the
  long word, the indented line, the leading tab that caught the first
  version, and the caret at a cut. The twenty-five existing wrap tests still
  hold.

## 2. Finishing

- [x] 2.1 No `.abydos/backlog/spec/*.md` is made untrue: the directory is
  gone from the tree.
- [x] 2.2 `make test` 4236 tests in 538 suites, exit 0 with the two standing known issues, load 42.2 over 10 cores; `make warnings` exit 0.
