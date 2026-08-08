# Split the editor by dragging tabs, or with ⌘\ and ⇧⌘\

`8698c44fb` · 2026-07-30

The editor area is now a tree of panes rather than a single tab strip. Each pane
is a full editor group with its own tabs, find bar and status line, so the two
halves are genuinely independent — not one document shown twice.

Dragging a tab shows the region the drop would occupy: the edges split, the
centre moves the tab into that group. Edge bands rather than quadrants, because
quadrants make it far too easy to split when you meant to reorder. Tabs move
between panes intact, carrying their document, scroll position and folds, rather
than being closed and reopened.

Splits nest: any pane can be split again in either direction, built from
two-child NSSplitViews. Emptying a pane collapses it and, when a split is left
with one child, the split itself is replaced by that child, so the tree never
accumulates redundant levels.

⌘\ and ⇧⌘\ *open* the current file in the new pane rather than moving it.
Moving would empty the source pane, which then collapses — so an explicit split
of a single-tab group would appear to do nothing. Two views of one file is also
what the command is usually for.

Fixes soft wrap not re-flowing when a pane's width changes: wrap width comes
from the viewport, so after a split the old width persisted and long lines were
clipped at the new edge instead of wrapping.

171 tests.
