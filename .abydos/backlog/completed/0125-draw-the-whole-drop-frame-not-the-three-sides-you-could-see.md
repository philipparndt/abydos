# Draw the whole drop frame, not the three sides you could see

`0d4d88553` · 2026-08-01

The outline marking where a dragged tab would land was missing its top edge.
The window draws its content the full height of the frame, so the editor
begins behind the titlebar, and an outline drawn at the top of that view is
covered by it — the first visible pixel of blue was the *bottom* edge, seven
hundred points down.

The overlay now starts below the titlebar, using the same inset the tab bar
already gets, and zones are worked out in the region they are drawn in so
what is highlighted is what the pointer is over. The stroke is also inset by
its whole width rather than half, since half of it fell outside the view at
the edges and was clipped away.
