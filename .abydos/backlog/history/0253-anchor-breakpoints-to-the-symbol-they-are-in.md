# Anchor breakpoints to the symbol they are in

`cb8a4b964` · 2026-08-04

A line number says nothing once a file has been rewritten, and the text
search that followed one was deliberately near-sighted: a `}` four
hundred lines away is a coincidence, not the same `}`. So a breakpoint
now also remembers the symbols it sits inside and how far into the
innermost one it was — "third line of Config.setUp" — which survives that
function moving four hundred lines because something above it changed.

Three claims, each weaker than the one before: the symbol, then the text
on the line, then nothing at all. A breakpoint moved to the wrong place
by a weak claim is worse than one that admits it does not know, so the
last answer really is nothing.

The pure part, with tests. Reading anchors off a file as it is loaded is
the next step; nothing yet writes them.
