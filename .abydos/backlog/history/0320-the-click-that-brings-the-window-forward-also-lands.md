# The click that brings the window forward also lands

`3ad3d6a5b` · 2026-08-06

macOS swallows the first click into an inactive window: the app comes to the
front and the click is thrown away, so it has to be made again. In an editor
that means somebody who clicked at a line to type there is left with the caret
where it was, and finds out one keystroke later. In a terminal it is worse,
because what the click is usually aimed at is a tmux pane, and choosing one is
the whole of what the click was for.

Both surfaces take it now. The pane change needs nothing else: a click in a
terminal with mouse reporting on is already forwarded to whatever is running
in it, which is how tmux hears about it — so this reaches the panes as well as
the window, which is the part Ghostty leaves out.

Only these two. A click in text moves a caret and a click in a terminal picks
a pane; neither closes, deletes or runs anything, which is what the default is
guarding against. Tabs keep their close buttons out of reach of a click that
was only meant to bring the window forward.
