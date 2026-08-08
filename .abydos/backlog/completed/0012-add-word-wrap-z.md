# Add word wrap (⌥⌘Z)

`19c51bcd2` · 2026-07-30

Soft wrap is tractable in this renderer only because the editor uses a
fixed-advance font: a line's row count is ceil(columns / width), arithmetic
rather than typesetting. Per-line widths are prefix-summed once so both
directions of the row mapping are binary searches, which keeps scrolling cheap
on a large file.

Wrapping composes with folding rather than fighting it — hidden lines
contribute no rows — and each row draws only its own slice of the line, sliced
by UTF-16 offset so syntax and search highlight ranges stay valid without
re-mapping. Continuation rows leave the gutter blank, and the document stops
scrolling horizontally since there is nothing to scroll to.

The preference persists and applies to every open editor.

149 tests.
