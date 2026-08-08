# Report the right button while it is held

`d6bbdea80` · 2026-08-03

A tmux menu is press-drag-release: the manual says releasing with an item
selected chooses it, and releasing with nothing selected closes the menu. So
the highlight follows a *drag*, not a hover — and dragging with the right
button was the one thing this terminal never reported. It reported left
drags, presses and releases, and nothing at all for the other two buttons.

Right and middle now report their drags, and motion with no button held is
reported for programs that ask for every event, once per cell rather than
once per pixel. Motion is skipped while a button is down, since that is a
drag and reports itself, and a report is only sent once the pointer leaves
the cell it was last seen in — a menu waiting for the pointer to move
somewhere should not be told it is still where it was.

Proved against a program that asks for every event and prints what arrives:

    ^[[<2;12;11M    press, right button
    ^[[<34;14;9M    right button, moved      <- these are new
    ^[[<34;14;8M
