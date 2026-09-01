## Context

The log page folds a merge: the commits the merge brought in stop being rows,
and the merge row says how many it is holding. That part works. The graph beside
the rows is laid out separately, over every commit, and then the rows are
filtered — so the two disagree about which commits exist.

## Goals / Non-Goals

**Goals:**

- A folded merge's branch leaves no lanes behind.
- The graph and the rows are computed from one list.

**Non-Goals:**

- Changing what folding hides, or the fold control, or the count on the merge
  row. Those are right.
- Redrawing the lane algorithm. It is given better input, not rewritten.

## Decisions

**Lay out what will be drawn.** The order becomes: work out what is hidden,
build the visible list, lay the graph out over that. One list, one layout,
nothing to filter afterwards.

*Ruled out: filtering the lanes out of each `Place` after the fact.* It is the
same mistake one layer down — a lane's presence in a row is a consequence of the
layout, and editing consequences instead of inputs is how the two come to
disagree in a second way later.

**A collapsed merge's hidden parents are dropped from the node handed in.** The
merge keeps its first parent, which is still drawn. Its second parent is the tip
of the branch being hidden, and leaving it in would have the layout reserve a
lane for a commit it never reaches — the same dangling line by a shorter route.

*Ruled out: leaving the parent and trusting the layout to cope.* Worth stating
because it is the tempting smaller diff, and it reintroduces the bug.

## What implementing it changed about this design

**The decision above was wrong, and driving it is what said so.** "Lay out what
will be drawn" was right about *where* the fix goes — the input — and wrong
about what the input should be.

Filtering the commits and stripping the merge's hidden parent did remove the
lanes. It also stopped the merge being a merge: with one parent it has nothing
to fold, so `collapsible` came out zero, `CommitRowView` draws no fold marker
without it, and **a folded merge could never be opened again**. Driven, the
first attempt read `rows 9 -> 6` and then `rows 6 -> 6` — folded, and stuck.

So the whole history goes into the layout and a `hidden` set says what is off
screen. `collapsible` keeps counting what a merge brought in, which is a fact
about the history rather than about what is drawn, and no lane is opened for a
commit nobody will see.

Then a second driven run said `dangling=1` while folded, and that was the same
mistake one level down: leaving a hidden commit's *row* out is not enough,
because the commit still walks the layout, and nothing is waiting for it, so it
opens a lane of its own — which then carries down through every visible row
below. A hidden commit takes no part in the walk at all now.

Both were found by running it. Neither would have been found by reading, and the
first one is worse than the bug it was fixing.

## Risks / Trade-offs

**Lane colours may shift when a merge is folded**, because a lane's index comes
from the layout and the layout now sees fewer branches. → That is honest: the
picture is of what is showing. Worth checking a fold and an unfold return to the
same picture, which is a driven claim rather than an argument.

**Folding and the faded remote-only lanes interact.** `rebuildFadedLanes` walks
`visible` and is computed after, so it should be unaffected. → Should be, not
is: it is checked rather than assumed, because both features draw lanes and
neither knew about the other when it was written.
