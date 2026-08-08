# Breakpoints find their code again after somebody else rewrites the file

`1d8483f30` · 2026-08-04

The anchor existed but nothing wrote one. Now a breakpoint records the
symbol it sits inside the moment it is set, keeps that up to date as the
file is edited, and reads it back when the file is re-read from disk —
which is what an agent, a `git checkout` and a formatter all leave
behind, none of them saying what they changed.

Working out what lines a symbol covers turned out to be the hard part.
The parser will not say: several grammars, Swift's among them, hang a
method's `@definition` capture on the enclosing type, so every member of
a type claims the type's whole range and a line inside one method reads
as being inside all of them. `SymbolOutline.lineSpans` derives the spans
from the outline's own nesting instead — a symbol runs from its
declaration to where the next thing at its level starts.

Two things only the running app found:

A file being written without a temporary file is briefly empty. Resolving
against that truncation moved every breakpoint to line 1 and anchored it
there, throwing away where it belonged a fraction of a second before the
real text arrived. One that cannot be found is now left entirely alone,
line and anchor both, so the text landing a moment later still has
something to match. Nothing is clamped into a shorter file either: the
last line is code nobody chose.

Counting lines into a symbol slips the moment one is taken out above the
breakpoint but inside the same function, which is most of what editing a
function is — a rewrite that dropped one line moved a breakpoint from
`start()` onto `finish()`. The symbol now says which function and the
text says which line of it, searched for only within that symbol: a
`start()` in the function below is a different `start()`.

`--breakpoint-report <seconds>`, repeatable, prints where each breakpoint
is and what it believes it is on. Anchoring is invisible until a file is
rewritten under it, and a gutter only says which line.
