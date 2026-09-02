## Context

The tree colours a changed file's name through `Theme.color(for:)` and draws no
other mark. Folders already carry the rolled-up state, which is why a folder
holding a change is green.

## Goals / Non-Goals

**Goals:**

- A change visible as a mark on the row, not only as a shade of the text.
- Useful on a collapsed folder, which is where the file itself cannot be seen.

**Non-Goals:**

- Taking the colour off the names. That is the signal people have now, and
  removing it in the same change as adding another would leave nobody able to
  say which of the two they were reacting to.
- Letters instead of dots (`M`, `U`, `A`). Considered, because the commit page
  draws exactly those badges — but the commit page is a list of changes where
  the kind is the useful distinction, and the tree is a list of *files* where
  the useful distinction is changed or not. A dot answers that at a glance and
  a letter has to be read.
- The other trees. The branches tree and the changes tree are lists of changes
  already; marking them would say nothing.

## Decisions

**One dot, at the trailing edge, in the state's own colour.** The same colour
the name takes, so a row says one thing twice rather than two things once.

*Ruled out: a fixed accent colour for every state.* Then a conflicted file and
a modified one look identical, and the tree already distinguishes them.

**Ignored draws nothing, and neither does unmodified.** In a project with a
build directory the ignored rows outnumber everything else, and a mark on
nearly every row is furniture.

**Room first.** The navigator is 4182 lines against a recorded 4222, so this
fits — but only because two classes were moved out of it earlier today. If it
had not fitted, the mark would still not justify making that file bigger.

## What the capture found

**The mark was drawn off screen**, and nothing but a capture would have said so.
`bounds.maxX` is the trailing edge of the *cell*, and the tree's column is sized
to its widest row — the root carries the project's whole path as a subtitle — so
a cell is routinely wider than the pane. The first driven capture had no dots in
it anywhere, with code that was drawing them the whole time.

The mark is pinned to the visible edge now: the clip view's bounds, converted,
and the lesser of that and the cell's own edge.

**And then the mark ran under the name.** Reported from the next build: in a
narrow pane a long name was drawn over the dot. The two were measured against
different edges — the name against the cell's width, the mark against the
visible edge — which agree until the pane is narrow enough that they do not.
Both use `markEdge` now, and because it is derived from the clip view it moves
with the scroll: a name scrolled into view gains exactly the room the mark
gives up.

## Risks / Trade-offs

**A dot at the trailing edge competes with the subtitle.** Dependency notes and
session rows draw grey text there. → The mark takes its width off what the name
and subtitle are given, so they truncate before reaching it rather than drawing
underneath.

**Two signals for one fact could read as two facts.** → Same colour, and the
dot is small: it is the same sentence said twice, which is how a status is
usually shown.
