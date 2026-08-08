# Build without warnings again

`a6f6c25e4` · 2026-08-04

Three, and the interesting one is the puff. macOS 14 deprecated
`NSAnimationEffect`, and what it points at instead is the same puff as a
cursor: it is set when a breakpoint is dragged clear of the gutter and
put back on mouse-up, so a marker still leaves visibly rather than merely
vanishing. The deletion happens where it always did — only the animation
became a cursor.

The other two say what they are. `debuggable` was left behind when the
decision it fed moved to the moment a goal is clicked, which the comment
below it already explains, and the backup path `setStatusHidden` returns
is genuinely not wanted where a line this app wrote itself is taken out
again.
