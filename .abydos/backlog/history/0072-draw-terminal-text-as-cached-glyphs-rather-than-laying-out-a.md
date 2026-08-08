# Draw terminal text as cached glyphs rather than laying out a string per run

`5591a7d8f` · 2026-08-01

A screen where every cell has its own colour goes from 14.0 to 4.6 ms a
frame, ordinary output from 2.4 to 1.0, and the fire benchmark from 374 to
826 fps in the same pane.

Each run of matching attributes was built into an NSAttributedString and
drawn, which typesets the text from scratch every time. That is affordable
while a run is a whole line of one colour. The fire benchmark changes colour
on every cell, so a row of 233 columns is 233 runs, and a frame was ten
thousand typesetting jobs — measured at 5.8x the cost of the same screen in
ordinary colours.

Characters are now turned into glyphs once and remembered, then drawn
straight through CTFontDrawGlyphs with a position per cell. Anything the
terminal's own face cannot draw — emoji, CJK, the powerline range — is looked
up through CoreText's fallback once and remembered with the font that had it,
so a run breaks into batches only where a fallback was actually needed.

Underline and strikethrough came free with the attributed string and are now
drawn as rects, positioned off the same baseline as the glyphs.

One deliberate loss: `->` no longer becomes an arrow. Ligatures need the run
shaped as a whole, and a terminal is a grid of one glyph per cell — which is
why the old code already split runs at every double-width character to stop
the text drifting off the grid. Everything else renders as it did: checked
against a reference screenshot of bold, italic, underline, strikethrough,
emoji, CJK, accents, truecolour, dim and indexed colour.
