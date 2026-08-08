# Fix the crash on hovering a debug button, and draw the step glyphs

`4f4e8b503` · 2026-08-01

Hovering crashed. The tooltip was registered with a bridged string as its
owner, and AppKit does not retain the owner — by the time somebody pointed at
a button, what it read back had been freed. The view owns them now, with the
text kept beside the tags it was given, and they are registered when the
layout changes rather than from inside `draw`, which is no place to be
mutating tracking state.

The stepping icons are drawn rather than borrowed. No SF Symbol says "step
over": the nearest are corner arrows that read as "into" or "out" just as
readily, which is useless on a row of three buttons that differ only in
that — hence "there is no step over" about a button that was there and
working. They now say what every debugger has said for twenty years: an arc
hopping over the call, an arrow down into it, an arrow back up out of it,
with the call itself as a dot underneath.

Verified by rendering the toolbar to an image and by asking for every
tooltip through the same call AppKit makes on hover.
