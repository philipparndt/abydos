# Colour the debug console, and tint the run strip while it runs

`6b98db424` · 2026-08-01

The console is the terminal with nothing behind it: a program under the
debugger prints the same escape sequences it prints anywhere else, and
showing them as text was the only thing making the two look different.
A change of speaker mid-line now starts a line, so Delve's "Building..."
no longer runs into its next sentence.

Running colours the toolbar's own glass rather than painting a rectangle
on top of it. Offscreen captures of glass come back blank, so the
screenshot harness turns it off.
