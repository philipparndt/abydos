# Abydos 0.20.3

## The boxes on a card's tip can be reached

Hovering a card in progress lists its open tasks under it, each with a box to
tick. On every card but the last of its column, the list could not be reached:
the pointer travelling down to it closed the tip on the way.

The tip opens under its card, and the next card of the column lies between the
two, so the journey crosses that card. Two faults, one behind the other.
Touching the card below closed the tip at once, because another card in
progress took the tip's place without waiting — the last card of a column was
the only one that worked, being the only one with empty space below it rather
than another card. With that fixed the crossing still *moved* the open tip,
because one set of remembered coordinates served both the card a tip is drawn
under and the card a wait is running for: the next redraw placed the tip under
a card it was not about, out from under the pointer reaching for it.

Both are gone. The tip is now driven with real pointer moves posted from
outside the app, since whether a journey closes a tip is not a question the
process making the journey can answer about itself.

## Ticking several things, and taking any of them back

Every task ticked while the tip is open now keeps its own row, dimmed, with
*Undo* beside it, and they can be pressed in any order. Only the newest tick
was undoable before: the second tick took the first one's way back off the
screen. ⌘Z still takes back the newest, and closing the tip hands the job to
the board's undo, as it always did.

*Undo* is drawn at the row's trailing edge now, with the task's words wrapping
short of it. Written after the words, it flowed past the bottom of a row capped
at two lines — which most tasks fill — so the one row whose action is not the
obvious one was the row that could not say so.

## Tasks read as they were written

The tasks in that list come out of a markdown checklist and were drawn exactly
as the file has them, asterisks and backticks included. They are drawn as they
were meant now: bold where the file has `**`, a fixed-pitch face where it has
backticks. A marker with no closing partner stays the character it is,
`width * height` is not italic, and underscores are left alone — a pair of them
in this prose is nearly always one identifier rather than emphasis.

## A rewritten file compares better

`abydos-diff`, and the compare page it opens, describe a heavily rewritten file
much more closely than they did. The line diff gave up early on exactly the
files that most need it: a wholesale rewrite has most of its lines on one side
only, so the search saw an edit distance far larger than the number of lines
that could ever pair up, exhausted its budget, and split at a point it had not
reasoned about.

Lines that can match nothing are now taken out before the search — a line
appearing nowhere on the other side can be in no common subsequence, so
removing it changes none of them — and the budget, no longer the only guard,
can afford to be four times more generous. Measured over 1,927 revisions of
this repository's own files, ours was a longer diff than git's on eighteen of
them before, worst 9,932 changed lines against git's 3,640 on a file of ten
thousand; it is now longer on one, by a single line, and shorter than git's
over the corpus as a whole, at the same speed.

The measurement that found this was taken to answer a different question —
whether the diff should use patience or histogram refinement instead of plain
Myers. It should not: git implements all three, and they describe 97% of real
edits identically.
