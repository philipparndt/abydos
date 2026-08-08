# Panel tabs, drawn the way editor tabs are

`6062ad882` · 2026-08-02

Same shape, same icon-then-name, same accent under the one in front, and an
icon per kind: a terminal, a ladybird for the debugger, a gauge for the
profiler, sparkles for a review. A terminal is a tab like any other and the
panel had no reason for a style of its own.

Two things the split had lost. The drop preview was being drawn behind the
pane — a terminal fills its column, so a highlight under it is a highlight
nobody sees; it is drawn over the pane now. And a tab dropped on a strip
carries which column it came from, so dropping it on the other column's tabs
moves it there rather than being read as a reorder of a list it was never in.
That is how a split is undone by hand.
