# Terminals: a drop target you can see, and a way back in

`fd2cc65aa` · 2026-08-02

Dropping a tab on the pane did not work because the pane is covered by
whatever is running in it, and a drag has to land somewhere certain to see
it. A sheet of glass goes over the pane for the length of the drag: it takes
the drop, and it draws the half the terminal would land in — the same
preview the editor groups show.

A terminal pulled out into a window can be brought back. The window has the
one tab in it, so it can be dragged like any other, and dropping it in the
panel returns the running shell rather than starting a new one. Which panel
or window a dragged tab came from is looked up in a registry, since a
pasteboard carries bytes and not objects.

Closing a torn-off window still ends its shell — unless the terminal has
just been handed to somebody who wanted it.
