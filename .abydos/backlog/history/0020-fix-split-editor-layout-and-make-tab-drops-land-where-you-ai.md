# Fix split-editor layout and make tab drops land where you aim

`d85da8236` · 2026-07-31

Four problems with dragging tabs between panes:

- Every pane inset its tab bar by the window's titlebar height, which is
  only correct for a pane that actually touches the top. A pane below a
  horizontal split has the pane above it as a neighbour, not the
  titlebar, so it left a wide empty band between the two.

- The drop preview was drawn in the group's root view, so its own
  subviews painted over it and nothing was visible during a drag. It
  now lives in an overlay above them, and outlines the whole target
  region rather than marking one edge.

- EditorTabDrag describes zones with a top-left origin, but the view
  hit-testing them was unflipped, so "drag to the top" resolved to
  .bottom. Both the drop view and its overlay are now flipped to match.

- Dropping on a tab strip fell through to the pane beneath, which read
  the strip as the pane's top edge and split. The strip is now its own
  drop target: it shows an insertion caret and moves the tab into that
  group at the slot you released over, or reorders within the group.

The status line is now one per window rather than one per pane. Caret
position and language describe where you are working, and you work in
one pane; stacking a status bar under every pane repeated that for no
gain and ate vertical space.
