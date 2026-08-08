# A torn-off terminal window is a terminal area, not a single shell

`b241ee921` · 2026-08-02

It holds the same thing the panel holds: tabs, a +, renaming, dragging
between windows, and two terminals side by side. A terminal put on a second
display is still a terminal somebody works in, and a window that could only
ever hold the one shell meant going back to the main window to open another.

What it does not have is a panel's own controls. There is nothing to hide it
into, and following a shell's project belongs to a window that has one.
Terminals can be torn off out of these windows too, and closing one ends the
shells it holds.
