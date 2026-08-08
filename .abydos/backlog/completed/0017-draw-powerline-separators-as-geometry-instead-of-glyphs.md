# Draw powerline separators as geometry instead of glyphs

`96aeeb70c` · 2026-07-30

The bundled font was being used correctly — logging the resolved font confirms
HackNFM-Regular — but a font glyph is sized to the font's own metrics, not to
the terminal cell. That leaves a seam where one prompt segment meets the next
and a slight height mismatch against the segment background, which is what still
looked wrong after the font was fixed.

Separators (U+E0B0-B7, U+E0C0-C3) are now drawn as filled shapes sized exactly
to the cell, so segments meet with no gap and the prompt looks the same
regardless of which font is configured. Ghostty, Kitty and WezTerm all
special-case these glyphs for the same reason.
