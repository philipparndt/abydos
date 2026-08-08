# Syntax-highlight the code in a diff

`25ade15b8` · 2026-08-01

A diff was two colours: green for what arrived, red for what left. That
tells you what git did to the file and nothing about what the file says,
which is backwards — reading a diff is reading code, and the reason to
highlight code does not stop applying because it is under review.

A diff is not a program, though: it is two programs interleaved, each with
holes where the other one is. So each side is reconstructed before parsing —
context plus removals is the file as it was, context plus additions is the
file as it will be — and every line takes its colours from the side it
belongs to. Tree-sitter recovers well enough from the seams between hunks
that the result is worth having.

What the line does is still said by the marker and the tint behind it, which
is the part syntax colours must not take over. Above five thousand changed
lines the colours are skipped: a diff that size is a lockfile, and nobody
reads it line by line.
