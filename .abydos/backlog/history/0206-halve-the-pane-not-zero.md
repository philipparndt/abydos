# Halve the pane, not zero

`094a53ff9` · 2026-08-03

A split made from a gesture had no size yet, and the divider was placed a
runloop turn later from whatever bounds happened to be there — which for a
freshly-made split view is nothing at all. Halving nothing gives the new pane
nothing, and that is the split that opens as a sliver with only the text in
it.

The divider is placed at layout now, when there is finally something to
halve, and the split view keeps asking until there is.
