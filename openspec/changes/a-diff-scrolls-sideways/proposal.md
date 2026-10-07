## Why

Asked for on 2026-10-05, about the side-by-side diff on the pull request page:
"there is no scrollbar to the right in the diff view side by side if the text is
longer than what is shown. Other tools combine this with scrolling both sides
alongside. Not sure if that is always the best option — maybe a small icon like
a magnet beside the scrollbar to link them, and only then scroll both sides?"

**A line wider than its half cannot be read past the edge, at all.** `DiffView`
draws each half of a side-by-side row clipped to its column — "a long line runs
to the middle and stops" — and its scroll view has a vertical scroller only. The
document view is pinned to the clip view's width, so there is nothing to scroll
to even with a trackpad. The unified arrangement has the same fault with one
column instead of two; side by side only makes it common, because each half is
half as wide. A reviewer whose change is at column 140 of a line sees the first
seventy columns of it and has to check the branch out to read the rest.

It was already written down: the change that put a find bar over this diff
(`a-review-diff-can-be-searched-and-shown-side-by-side`) records as a risk that
a match past the right edge is selected but cannot be scrolled to. This change
is what that risk was waiting for.

There is no originating `.abydos/backlog` item: the backlog is retired and this
comes from a direct request.

## What Changes

- **Each half of a side-by-side diff scrolls sideways**, with a horizontal
  scroller along the bottom of each half, a trackpad swipe or ⇧-wheel over a
  half, and the line numbers staying put while the text moves.
- **A link between the two scrollers** — a chain-link button in the gap between
  them, where the rule between the halves meets the bottom edge. Linked, moving
  either half moves both by the same amount; unlinked, each half moves alone.
  **Linked is the default**: the halves of a row are nearly always the old and
  new version of the same line, and the change being read is at the same column
  in both. Unlinking is for the case where one side is much longer — a line that
  was rewrapped, a minified file on one side. What was chosen is remembered.
- **The unified diff scrolls sideways too**, with one scroller and no link,
  because the fault is the same there and a fix for one arrangement only would
  leave the switch between them changing whether a line can be read.
- **The current find match is scrolled sideways into view**, closing the risk
  the find change left open.
- **Every host of the diff gets it** — the changes pane, the log and commit
  pages, the stash page and the pull request page — because they all draw the
  same view and the fault is the view's.

## Capabilities

### New Capabilities

- `diff-sideways-scrolling`: reading a diff line past the edge of its column —
  the scrollers, what moves and what stays, linking the two halves, and how the
  find bar and the keyboard reach a column that is off screen.

### Modified Capabilities

(none — `diff-selection`'s requirements are unchanged: a selection still belongs
to one half and copies what it covers; this change moves where the text is
drawn, which the selection follows.)

## Impact

- `Sources/AbydosApp/Git/DiffView*.swift` — a horizontal offset per text column,
  applied where the text is drawn and where a point is turned into an offset;
  the widest line per column, for the scrollers' proportion; sideways wheel
  events. `DiffView.swift` is 531 lines and `DiffView+Selecting.swift` 522, so
  the scrolling goes in a file of its own.
- A small view for the scrollers and the link button, installed in the diff's
  enclosing scroll view so that it stays at the bottom while the rows scroll.
- `Sources/AbydosKit/Settings/Settings.swift` — one preference, whether the
  halves are linked.
- `Sources/AbydosApp/Git/DiffView+Search.swift` — revealing a match sideways.
- Driven-run verbs for the offsets and the link, on the pull request page's
  driver.
- Not the compare page's `FileCompareView`. Its spec says that with wrap off
  each half scrolls sideways; whether it does was not checked while proposing
  this, and it is a different view.
