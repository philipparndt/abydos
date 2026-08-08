# Tell a program where the pointer is

`a451ad548` · 2026-08-03

A terminal reports button presses, releases and drags, and this one did all
three — but nothing at all when the pointer merely moves. Mode 1003 is the
one that asks for that, and tmux turns it on while one of its own menus is
open: it is how the item under the pointer comes to be highlighted. Without
it the menu appears and then sits there, dead, which is what right-clicking a
tmux tab did.

The view now takes motion events while its window has the keyboard, and
reports them once per cell rather than once per pixel — a pointer crossing
eighty columns is eighty reports, not eight hundred.

Proved at the protocol level, with a program that asks for every event and
prints what arrives:

    ^[[<2;12;11M   press, right button
    ^[[<2;12;11m   release
    ^[[<35;14;9M   motion, no button   <- these are new
    ^[[<35;14;8M

35 is "no button held, and it moved", which is what a menu is waiting for.
