# Ask for the text form of a character before the emoji one

`90d32f3b7` · 2026-08-01

Claude Code puts a record mark before each of its answers, and it came out as
a coloured button in a rounded box sitting in the middle of a paragraph.
Ghostty draws a bullet, which is what the character means there.

U+23FA is an emoji by default even though it reads as a symbol, so CoreText
hands back Apple Color Emoji for it. A grid of one glyph per cell has no room
for a picture. The fallback now asks for the text form first — U+FE0E is how
that is asked for — and only takes a colour font when nothing has a text
form, so a real emoji is still an emoji.

Both renderers go through the same lookup.
