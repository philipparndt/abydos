# Abydos 0.21.2

## The markdown preview is set like a page

A fenced code block is one panel: padded, rounded, in the theme's current-line
colour, with the code's own line spacing inside it and no blank line between
its lines. A fence with no language is set in the text colour, not git's
green. Headings step down from twice the body with a rule under the first two
levels, paragraphs get a line's worth of air, inline code sits on a pill, a
list marker hangs in the margin, a quote carries a bar down its left edge, and
`---` is a drawn line. Every size follows ⌘+ with the rest of the window. The
commit message in git history is set the same way.

## TypeScript is coloured as fully as JavaScript

A `.ts` or `.tsx` file, and a `ts` fence in a preview, coloured only the
identifiers beginning with a capital: the grammar's own highlight query is
thirty-five lines of type patterns and expects to inherit JavaScript's.
It does now — keywords, strings, calls and comments as in a `.js` file, types
on top — and a test compiles the joined query so a grammar bump that breaks it
is a red test rather than a file quietly left in one colour.
