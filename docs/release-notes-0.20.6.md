# Abydos 0.20.6

One addition, from a report with a screenshot of the tree's menu open on a
changed file: every way of looking at it, and no way to put it back.

## A file's changes can be discarded from the tree

Right-click a changed file or folder and *Discard Changes* puts it back the way
the last commit had it — the same question, the same safety-net ref and the
same toast the Changes pane gives, reached from the row you were looking at. A
folder says how many files it will take and how many of those git has never
seen; a file whose only change is staged is not offered, exactly as the pane
does not offer it, and neither is a conflict. An open editor tab reloads, and a
compare tab on the file shows there is nothing left to compare.

## Four panes now follow the zoom

The Backlog pane's *List / Board* switch and the buttons beside it, the
Structure pane's filter field and its empty label, and the Scratches pane's
search field grow and shrink with everything else, as the pull-request list's
controls already did. The Scratches rows and section headers are re-measured
at the new size rather than waiting for the next reload.

## Waiting is a hairline, not a box

A pane asking GitHub or git for its rows, a model being built or a diagram
being drawn, shows a thin sweep of colour under its header — or along its top
edge where it has none — instead of a boxed spinner in the middle. Rows
already on screen stay where they are, and the pane says what it is waiting
for only where there is room to, adding that it is still waiting after five
seconds. The project tree and the Backlog pane show it too, and the tree's
header gains a refresh button beside its other three that re-reads the folder
and the working copy's status.
