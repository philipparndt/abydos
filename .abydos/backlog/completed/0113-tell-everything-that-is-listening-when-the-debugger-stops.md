# Tell everything that is listening when the debugger stops

`f668f5552` · 2026-08-01

The debug toolbar sat greyed out and saying "Not running" while the program
was plainly stopped, with its stack and locals on screen beside it.

Both the pane and the window need to know about state changes — one enables
its buttons, the other clears the execution marker — and both assigned
`onStateChange`. It was a single closure, so the second assignment silently
replaced the first and the toolbar never heard anything after the state it
was born in. The same was true of `onStoppedAt`.

Both are lists of observers now, so wanting to know is not something one
part of the app can take away from another.

Also fixes the completion list, which AppKit was drawing as an inset rounded
capsule floating inside each row: in a list two hundred points wide that is
most of the popup, and it clipped the very text it was showing. Plain rows,
overlay scrollers, and placed clear of the line being completed rather than
on top of it.
