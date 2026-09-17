# Abydos 0.21.2

## The title bar zooms from the right of the run buttons too

Double-clicking the strip beside the play and debug buttons and the
configuration well now zooms the window, as double-clicking between the
project capsule and the buttons always did. The message about the last run
has moved to make that true: it sits just left of the play button, in the
same red for a failure and with the same cross to forget it, and
double-clicking it zooms the window too. In a narrow window the capsule
shortens its names to the room there is, then folds away, and the pills after
it; there is no overflow menu any more, and the strip beside the buttons stays
free to double-click however narrow the window gets. Switch Project and the
branch menu are in the menu bar as before.

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
