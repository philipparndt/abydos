# Drag an editor tab out into a window of its own, and back

`4f5750e3e` · 2026-07-31

Releasing a tab outside the window it came from opens a window on the spot,
which is how it reaches a second display: the screen chosen is the one under
the pointer, not the one the tab left. The window is placed under the cursor
and nudged so all of it is on that screen, however near an edge it was
dropped.

Dragging it back needed more than the drop targets already had. A drag
carries the identifier of the group it started in, and both drop paths
looked for that group among their own window's groups only — so a tab from
another window matched nothing and the drop was quietly ignored. Areas now
register themselves, and a drop that cannot find the group nearby asks the
other windows for it. A window made by tearing off closes once its last tab
is taken back, rather than being left behind empty.

Opening a project skips torn-off windows when looking for one that already
has it open, so it raises the window the project was opened in.

Verified through --tear-off, which runs both directions along the real code
paths: two windows with a tab each, then one window with both and the torn
window gone. Where the window lands is covered by tests, including drops at
every corner and onto a second display.
