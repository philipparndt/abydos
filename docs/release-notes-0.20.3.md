# Abydos 0.20.3

## The boxes on a card's tip can be reached

The pointer travelling down to a card's task list crossed the next card,
which closed or moved the tip. It stays put now.

## Ticking several tasks, and undoing any of them

Every task ticked while the tip is open keeps its own dimmed row with *Undo*
at its trailing edge, and ⌘Z takes back the newest.

## Tasks read as they were written

Tasks from a markdown checklist are drawn bold where the file has `**` and
fixed-pitch where it has backticks. An unmatched marker and underscores are
left alone.

## A rewritten file compares better

The line diff in `abydos-diff` and the compare page exhausted its budget on
wholesale rewrites and split badly. Lines that match nothing are removed
before the search and the budget is four times larger. Over 1,927 revisions
of this repository it was longer than git's on eighteen files; now on one, by
a line, and shorter over the whole corpus at the same speed.
