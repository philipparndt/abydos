# The layout decides what a key means, so every keyboard's dead keys work

`6243dea24` · 2026-08-07

`^` and `` ` `` could not be typed in the terminal at all. Both are dead keys
on a German layout: they carry no character until a second key arrives, and
every event was being turned into bytes here — where there was nothing to
turn into anything. The fix is not a table of those two keys but the door
they come through, which is the door every layout and every input method in
the world uses: an event with no character of its own now goes to the input
manager, the half-finished text is drawn underlined at the cursor, and what
the layout commits is what the program is sent. A key the input manager
hands back — Return while an accent is pending — is still sent.

Also in the terminal: pictures were drawn upside down by the CoreGraphics
path, which is what screenshots use and what a machine without Metal draws
with. And `abydos-icat` sized itself by guessing that a column is a pixel,
so a thousand-pixel picture claimed five hundred rows and left a page of
blank lines after every image; it now asks the pty — or tmux, which knows
better inside a session — how large a cell is.

`firebench` ships with the app as `abydos-bench`, beside `abydos-icat`: the
question it answers is about the build that is installed, not about a
checkout somebody still has to find.

In the editor, a short file left the view as tall as its text, so clicking
in the empty space below the last line reached the scroll view and did
nothing. The view now fills the viewport, where that click lands on the
last line.

And one line marks the tab that is showing, in one thickness for both
strips: the accent belongs to the pane the cursor is in, and every other
strip draws it plain. Drawing the editor's line before the hairline that
breaks under the active tab was painting out half of it, which is why it
looked thinner than the panel's.
