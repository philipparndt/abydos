## 1. Name them

- [x] 1.1 A `TrailingControl` for the strip's trailing controls, with one hit
  test used by the hover and the tooltips alike.
- [x] 1.2 One function holding what each of them says.

## 2. Light them

- [x] 2.1 `updateHover` tracks which control is under the pointer, and
  `clearHover` forgets it.
- [x] 2.2 A ground is drawn under it — a capsule at twice the strength for the
  pill and the tag, which have grounds of their own.

## 3. Say them

- [x] 3.1 Tooltip rects for each control, answered from the point.
- [x] 3.2 Re-registered when a frame moves and not on every layout.

## 4. Checked

- [x] 4.1 `--hover-control <name>` puts the pointer on one and prints whether
  it lit and what it says.
- [x] 4.2 Driven for the pill, the follow button, maximise and hide: all four
  lit, and the pill read "1 working, 1 waiting for you" with the two colours
  explained.
- [x] 4.3 **Against the pixels**, since "computed but never drawn" happened on
  this same strip earlier: the same crop from a hovered and an unhovered run.
  The chevron showed a band and the pill showed none, which is what sent the
  pill's halo to twice the strength; re-shot, it reads.
- [x] 4.4 `make test` and `make warnings`, both clean by their exit codes.
  4038 tests in 514 suites, exit 0, at load 8.7 over 14 cores; `make warnings`
  exit 0.
