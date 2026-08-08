# Keep the project tree where it was put

`6beb97eb6` · 2026-08-02

The split view was re-dividing the window whenever what sits in the editor
changed shape — opening the launch page made the tree jump from 260 points
to 492, and setting the divider back did not hold because the next layout
pass moved it again. The tree's width is a constraint now, and the only
thing that changes the constraint is dragging the divider. Its contents can
no longer demand a width either: a row showing a long path has an enormous
natural size, and it is meant to be truncated.

Also in this pass: the rename field on a terminal tab centres its text
rather than sitting it against the top of the tab; the files list on the
launch page puts its hint under the files instead of printing it through the
last one; and writing a new configuration reports a failure instead of
dropping it.
