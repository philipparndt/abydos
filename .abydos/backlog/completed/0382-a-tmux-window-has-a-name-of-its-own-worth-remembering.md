# A tmux window has a name of its own worth remembering

`45f26a0fd` · 2026-08-08

Groundwork for coming back to the window somebody was in. An index is
where a window sits, and somebody's window does not stay there: close the
one before it and every index after moves down, so coming back to
"window 3" is coming back to whatever slid into the gap. tmux's own id —
`@7` — survives renaming, renumbering and moving, and is what a memory of
"the window I was in" has to be made of.

Read from `list-windows`, and taken off the front of the line by
recognising it rather than by asking the split for one more field. A
window name can hold a semicolon — there is already a fixture for one —
so the number of fields is not something to count on. The first attempt
did count, and dropped every window whose name had a semicolon in it;
the existing fixtures caught it, which is the whole reason to have them.

A line with no id is the older shape and still reads, since a format is a
thing two versions of this can disagree about for one launch.

`select(windowID:inSession:)` goes back to one, and answers whether it
was still there — a no being ordinary rather than a problem: the server
was restarted, or the window was closed, and the answer is to carry on
with whatever tmux chose.
