# Wire the GPU renderer into the terminal, behind a setting

`af43386f3` · 2026-08-01

Off by default, under Settings as "GPU terminal rendering". Measured against
the CoreGraphics path on the same screen at 153x38: 160 fps against 114.

The view spans every line of history, which no drawable can be, so the layer
rides on top of the part that is on screen and is told where that is as the
view scrolls. The selection and the cursor become instances of their own,
drawn after the cells so they lie over them.

Damage tracking is skipped on this path: the GPU redraws what is on screen,
and what that costs does not depend on how much of it changed. Working out
what to keep would cost more than keeping it.

One way to ask for a repaint now, since marking the view for display reaches
CoreGraphics only. Replacing the old calls with it also replaced the one
inside the helper itself, which made it call itself forever and froze the
app on any terminal at all — including with the setting off. Caught by
sampling a hung process, which put the whole three seconds inside that one
function.
