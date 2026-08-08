# A picture in a documentation folder is something to look at, not a hex dump

`7067a1d23` · 2026-08-07

Opening a PNG in the editor said "This looks like a binary file" and offered
a hex viewer, which answers a question nobody asked: documentation lives
beside the diagrams and screenshots it talks about. A picture now opens as
the picture — fitted to the pane, never blown up past its own size, on a
checkerboard so a transparent background reads as transparent rather than as
whatever colour happens to be behind it. An SVG is a drawing that is also a
file somebody edits, so it opens rendered and keeps its source a click away.

The strip's empty part answers a right-click too, with the two things it can
make: a scratch for this project and one belonging to none. Double-click
already made the first; a menu is how anybody finds out either exists, and
the only way to reach the global one without the Scratches pane. Those global
ones are tinted differently wherever they are listed — in a strip of tabs a
note meant to outlive the checkout is easy to mistake for one of its files.

Two things that could not be used at all:

A picture printed inside tmux stayed on the screen for good. Nothing in the
protocol says clearing the screen takes a picture away, and no program sends
a delete for one it drew — least of all tmux, which repaints over what it
cannot see. Erasing rows now takes the pictures standing on them, so `clear`
does what it looks like it does.

And the commit message's details field refused the caret. A text view in a
scroll view is not any size at all until it is told how to resize, so the
box on screen was empty space and every click fell through it to the scroll
view behind.

Both harnesses go through the window's own hit testing rather than calling
the view: what was wrong in each case was that the click never arrived, and a
test that dispatched the event by hand would have agreed with the code while
the field stayed impossible to use.
