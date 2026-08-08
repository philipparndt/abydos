# Give the titlebar pills room inside their frames

`44d37746a` · 2026-08-01

The toolbar draws a rounded background behind each item, and a highlight
running to the very edge of it read as two frames on top of each other
rather than as one pill being pointed at. Each pill now sits inset, so
its own shape has margin and the two no longer touch.

Highlighted by darkening rather than lightening, because that background
is pale and white over white says nothing.
