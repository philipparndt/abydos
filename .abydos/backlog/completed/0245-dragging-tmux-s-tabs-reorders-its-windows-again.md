# Dragging tmux's tabs reorders its windows again

`9b5f4f946` · 2026-08-04

Moving tmux's windows to a strip of their own took the drag with it: the
new strip was given something to pick up — `canDrag` and `onMove` — but
was never registered for the drop, so a dragged tab had nowhere to land
and nothing happened. It takes tabs from itself only; a tab from another
panel or another window cannot become a tmux window.

Checked against a real server rather than by eye: dragging the first tab
to the end gives `0:second 1:third 2:first`, and dragging it back gives
`0:first 1:second 2:third`.

Also, tabs meet on that strip now. Everywhere else the two points
between tabs are the panel's background and read as a gap; there they
are the green bar, and a sliver of it down the side of the tab you are in
looked like a frame around it. The green line along the top stays — that
is the one that says which window you are in.
