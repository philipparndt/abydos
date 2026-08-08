# Wrap and scroll by display width, not by byte or character count

`3580150e0` · 2026-07-31

Soft wrap cut each row after a fixed number of UTF-16 units while the
row count was derived from display columns. A tab is one unit and up to
four columns, so a row of tab-indented code rendered wider than the
space it had been measured for; the overflow was clipped and those
characters appeared on no row at all. Rows are now cut where the text
actually reaches the edge, and a tab that would cross it moves whole,
since it cannot be split. Caret-to-row mapping follows the same rule, or
the caret lands on a row that does not show it.

The horizontal scroll range had the same fault from the other side: it
was sized from the longest line's *byte* length, which is too narrow for
tab-indented code — there was no way to scroll to the end of the longest
line — and too wide for anything non-ASCII. It is measured in display
columns now, with continuation bytes not counted twice.

Also: --wrap in the screenshot harness set the persisted setting rather
than toggling it. Toggling made each capture depend on how the previous
run happened to leave it, which is how a correct render came out looking
like a regression.
