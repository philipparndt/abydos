# Split the preview either way, and let the divider go where you drag it

`318a465a7` · 2026-07-31

Two split modes rather than one: Split Right puts the preview beside the
source, Split Down puts it underneath. Named the way the editor's own
splits are, so the name says where the new pane goes.

The divider now moves nearly edge to edge. NSSplitView otherwise honours
the panes' own minimum widths, and a code view with a gutter and a
rendered document each claim a fair share, so it stopped well short of
either side — but the point of a split is to glance at one while working
in the other, which means being able to give a pane nearly everything.
A sliver is kept either side: a pane pushed all the way out still has a
divider to drag back, and neither pane may collapse, since a collapsed
one leaves nothing to grab.

Resizing the window keeps the proportion rather than giving every new
pixel to one side.
