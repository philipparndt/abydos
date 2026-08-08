# Split the panel the way the editor splits

`514e13c73` · 2026-08-02

You were right that it was fundamental. One strip across two panes cannot say
which side a tab belongs to, so every question after that — which tab is
showing, where a new terminal goes, what a click means, which pane a drop
lands in — was answered by guessing, and the guesses kept disagreeing with
each other.

Each side has its own tabs now. A session carries which column it is in, and
that is the whole of what a split is: some tabs over here and some over
there. A new terminal opens in the column that has the focus; a click selects
within its own column; closing the last tab of a column collapses the split.
The panel's own controls stay on one strip, since there is one panel to hide
however many columns it holds.

"Put Beside, Left / Right" always ends in two columns, including when the tab
asked about is the one already showing — which is the tab somebody naturally
reaches for, and the case that did nothing at all. What goes beside it is
whatever else was showing, the pane used before it, or a new terminal.
