# Drag terminals: beside each other, or out into a window

`a23e9b06f` · 2026-08-02

A terminal tab can be picked up now. Dropped back in the strip it reorders;
dropped against the left or right edge of the pane it opens beside what is
already there — a shell next to the logs it is producing is the whole reason
for splitting a terminal area, and only left and right split, since
above-and-below inside a strip that is already short would give each of them
nothing. Dropped outside the window it becomes a window: one shell, no tabs,
because the point of pulling a terminal out is to put it on another display.

Terminal tabs and editor tabs do not accept each other's drags. They travel
on different pasteboard types, so a shell cannot be dropped into an editor
group and a file cannot be dropped into the panel.

Verified with the capture harness: two terminals side by side with their own
prompts, and a torn-off terminal opening as a 720x420 window beside the one
it came from.
