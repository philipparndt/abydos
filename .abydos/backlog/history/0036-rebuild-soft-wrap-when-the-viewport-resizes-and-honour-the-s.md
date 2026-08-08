# Rebuild soft wrap when the viewport resizes, and honour the scroll bar setting

`551943e48` · 2026-07-31

The wrap layout was built once and never rebuilt on a window resize, so
it kept allocating rows for the width it was measured at. Drawing
measured the viewport afresh, and the two disagreed: rows the layout had
allocated had nothing left to put in them, which showed as blank gaps
between wrapped lines. The layout is rebuilt when the clip view's frame
changes — bounds changes alone are scrolls, not resizes — and drawing now
slices with the columns the layout was actually built with, so even a
momentarily stale layout renders coherently instead of leaving holes.

Row counting moved to the same walk that slices the rows. Deriving it as
ceil(width / columns) disagrees whenever a tab has to move to the next
row whole: the arithmetic says one row, the walk needs two, and the
overflow lands on a row that was never allocated.

The editor also forced overlay scrollers, which overrides "Show scroll
bars: Always" in System Settings — so someone who had asked for
permanent scrollers never got them, and had no way to see there was
anything to scroll to. It follows the system preference now.
