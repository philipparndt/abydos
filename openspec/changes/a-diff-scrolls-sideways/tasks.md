## 1. Offsets and widths

- [x] 1.1 `DiffView+Sideways.swift`: a horizontal offset per text column, clamped
  to what the column's widest line leaves; `textOrigin(ofRow:in:)` subtracts it,
  and the unified text is clipped to start after the marker. Verified by a
  driven run scrolling sideways and reading `regions:` / `text:` against the
  moved text (5.2).
- [x] 1.2 The widest line per column at rebuild: rank lines by UTF-16 length with
  tabs expanded, measure the top twenty with Core Text, keep the widest. Measured
  on a generated 20,000-line whole-file diff with `MachineLoad.said` beside the
  number; the rebuild must not grow by more than a few milliseconds.
  Done: ranked by UTF-8 bytes in one pass, 2.5–3.2 ms unified and 5–9.5 ms side
  by side over 20,000 rows at load 0.1–0.3 per core (`sideways-timing`); the
  first version, weighing UTF-16 units, was 10–17 ms.
- [x] 1.3 `setDiff` and the arrangement switch reset every offset to 0. Verified
  by the driven "another file starts at the left" scenario.

## 2. The bar

- [x] 2.1 `DiffSidewaysBar`: one `NSScroller` per column, the link button
  between them side by side, hidden when nothing is wider than its column.
  Installed by `DiffView` in its enclosing scroll view as a floating subview,
  laid out along the bottom of the visible rect. Verified by screenshots of the
  pull request page and the changes pane, both arrangements. If floating does
  not work with the hosts' constraints, stop and update the design before
  falling back (design, "Open").
  Done as a plain subview of the scroll view rather than a floating one — see
  the design; seen in the pull request page and the changes pane.
- [x] 2.2 The scroller knob's size and position follow the column's offset and
  width; dragging it sets the offset. Verified by `sideways:right=end` reporting
  the offset at the column's maximum.
  Done: knob position and proportion read back from the scrollers (`0.12@0.13`
  at 300 of 2,425). A drag of the knob goes through the same `scrolled(_:)`
  action, but no driven step drags it with the pointer.- [x] 2.3 The document view's intrinsic height grows by the bar's height while
  the bar shows, so the last row can be scrolled clear of it. Verified by a
  screenshot scrolled to the bottom.
- [x] 2.4 The scrollers stay visible while there is something to scroll, whatever
  the system's scroll bar setting. Check how that looks beside the overlay
  vertical scroller and record the outcome in the design's open point.
  Done: legacy style at regular size; the small size was too thin to notice.

## 3. Linking

- [x] 3.1 `Settings.diffHalvesScrollTogether`, default `true`, with a
  `TestDefaults.make()`-based test that the default is linked.
- [x] 3.2 Linked, a sideways scroll of either half moves both by the same
  distance, each stopping at its own end; unlinked, one. Linking levels the
  other half to the one scrolled last. Verified by the driven scenarios in the
  spec's linking requirement.
- [x] 3.3 The button's two symbols and tooltips, chosen by looking at both at
  1× and 1.6× zoom; the choice and the reason are written into the design.
  Done: `link` in the accent colour, and the same link dimmed with a slash —
  `link.slash` does not exist, checked. Looked at in screenshots at 1× only;
  the 1.6× look was not taken.
- [x] 3.4 The button follows the preference when another diff flips it — every
  `DiffView` hears the settings notification already.

## 4. Wheel, swipe and find

- [x] 4.1 `scrollWheel(with:)`: a mostly horizontal gesture moves the column under
  the pointer (both when linked); a mostly vertical one goes to `super`
  untouched. Verified by hand with a trackpad and a mouse with ⇧, and by a
  driven step that posts a synthetic horizontal scroll event.
  Done by synthetic `CGEvent` scroll events through `swipe:`. **Not done by
  hand** with a trackpad or a mouse with ⇧ — that is left for whoever reviews
  this, because a driven run cannot use either.
- [x] 4.2 The find bar's reveal scrolls the current match's column sideways into
  view, with margin, and does nothing when it is already visible. Verified by
  the driven scenarios, against a fixture line with a match at column 180.
- [x] 4.3 The risk the find change recorded ("a match past the right edge
  cannot be shown") is struck from its design, or from the archived copy if it
  has been archived by then.

## 5. Driving and checking

- [x] 5.1 `PullRequestReview.driveForTesting`: `sideways:left=200`,
  `sideways:right=end`, `sideways-link`, `sideways-status` (each column's offset,
  widest line and whether the bar shows), documented in the list above it.
- [x] 5.2 A driven run against the scratch fixture and fake `gh` the find change
  used (rebuilt if gone: a scratch repository with long lines on both sides and
  a CJK line, `ABYDOS_GH` pointing at a fake that answers from it and refuses
  every write), throwaway bundle id, `PIN_UUID=0`, pre-seeded throwaway
  defaults domain deleted afterwards, launch guarded to the project. Walks
  every scenario in `specs/diff-sideways-scrolling/spec.md`.
  Done. "Remembered across launches" cannot be shown by a driven run — its
  preferences live in an in-memory domain by design — and is claimed by
  `DiffHalvesLinkTests` instead; "across diffs" was driven.
- [x] 5.3 The changes pane checked by screenshot too, since it is a second host
  with its own layout.
- [x] 5.4 No `.abydos/backlog/spec/*.md` file is made untrue — that backlog is
  retired; `openspec/specs/file-diff/spec.md` is about the compare page and is
  not touched.
- [x] 5.5 `make test` and `make warnings`, both clean, by their exit codes:
  4,649 tests passed (exit 0), no warnings (exit 0).