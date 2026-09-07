## Context

`WrapLayout` had three static walks over a line — `segmentRange`,
`segment(forOffset:)`, `rowCount` — each advancing by display width and
cutting when the next unit would overflow. Three copies of one rule, and the
file's own comments record what happens when two of them disagree: a segment
goes missing, or the caret lands on the wrong row.

## Goals / Non-Goals

**Goals:** cut at words; keep the tab rule; keep the caret rule for an offset
exactly at a cut; one walk.

**Non-Goals:** hyphenation, breaking after punctuation other than whitespace,
CJK line breaking, and a hanging indent for the continuation rows — each a
change of its own once this one has been read with.

## Decisions

### One walk produces the cuts; everything else reads them

`rowStarts` returns the offsets where rows begin. It fills a row by width and,
on overflow, cuts back to the last recorded word break on the row — the
offset just after a whitespace unit that came after a non-whitespace unit — or
at the edge when there is none. The three former walks become lookups over
that array.

*Ruled out:* patching the word rule into each of the three walks. That is how
they came to disagree the first time.

### Whitespace stays at the end of the row above

The cut is *after* the space, so the next row starts with the word. Every
editor that wraps prose does this, and a row starting with a space reads as
indented.

### Indentation does not count

`sawWord` is false until a non-whitespace unit has been seen on the row, and
a break is only recorded while it is true. Without it `\tabcdef` at six
columns cut after the tab and put the tab on a row of its own — which the
existing test for a leading tab caught at once.

## Risks / Trade-offs

- [A long URL in a Markdown paragraph] → it is one word and is cut at the
  edge, as before.
- [Layout cost] → the same single pass per question; `rowStarts` allocates a
  small array per line, which the callers already did for the units.
