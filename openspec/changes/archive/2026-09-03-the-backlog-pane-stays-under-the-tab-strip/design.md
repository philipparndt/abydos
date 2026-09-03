## Context

The bottom panel holds panes behind a tab strip. The backlog pane draws a header
of its own — the view control and the refresh verb — at the top of its bounds.
In the report those controls are drawn over the strip, so the pane's bounds
start above where they should.

## Goals / Non-Goals

**Goals:**

- The pane below the strip, deterministically.
- The cause named, because "sometimes" is what an ordering bug looks like from
  the outside and an unnamed one returns.

**Non-Goals:**

- Redesigning the backlog's header, which is fine where it belongs.
- The other panes, unless the cause turns out to be the panel's and therefore
  theirs too — in which case that is the finding and the scope grows on
  evidence.

## Decisions

**Diagnose before fixing, as with the tree reports.** Two of the three layers of
the staging fault in `one-tree-behaviour-everywhere` were fixed on plausible
readings before the real one was found, and each fix hid the next. An
intermittent layout fault is exactly the shape that punishes a plausible fix: it
will appear to work.

*Ruled out for now: pinning the pane's header below a hardcoded strip height.*
It would make the screenshot go away and would leave the pane wrong whenever the
strip is a different height — which it is at every zoom.

## Risks / Trade-offs

**It may not reproduce.** → Then the change fixes what can be shown to be wrong
about the ordering and says plainly that the report is not confirmed closed,
rather than claiming it.

## Open Questions

- ~~What makes it intermittent.~~ Answered above: a settings change on a project
  with OpenSpec changes and no `.abydos/backlog`.

## What it was

**Not an ordering.** Driven on 2026-09-03 with a measurement of the header
against the strip, on the four routes a person takes — a fresh window, a switch
onto the tab from a terminal, the panel maximised, a change of scale while
showing — the header sat exactly below the strip on every one, at 30 points, at
82 with the titlebar's inset, at 45 after the zoom. The panel places its panes
correctly and always did.

**Two predicates for one height.** `showContent` gives the header its 34 points
when the project has a backlog *or* OpenSpec changes, `hasSomething`, and hides
it otherwise. `applySettings` — which runs on every zoom, theme and presentation
change — gave it 34 points only for `hasBacklog`, and nought otherwise. This
repository moved its work to `openspec/changes` on 2026-09-01 and lost its
`.abydos/backlog` the same day; from then on the header was 34 points high on
opening and 0 high after the first settings change while the pane was up.

**And a zero-height stack view does not clip.** Its `List` / `Board` control
and `Refresh` kept their intrinsic height and were laid out around a
zero-height box at the pane's top edge — half of them above it, over the
strip. That is the screenshot: `List` under `tmux`, `Refresh` under the
trailing controls. *Sometimes* was "after a zoom, a theme or presentation mode,
on a project with no backlog folder" — which, the day it was reported, this
project had just become.

**The other panes were checked for the same shape** — a height set on a
settings change from a predicate other than the one that set it on load. The
search pane sets one height from `isNarrow` in both places; none of the others
sets a height in `applySettings` at all. The fault was the backlog's own.

**The fix** is one rule for the height, read in both places, and the header
hidden whole where it has nothing to say, so no control of it can draw outside
a box of no height. The design's ruled-out fix — pinning below a hardcoded strip
height — would have moved the fault, not found it: the header would have drawn
over the pane's own content instead.
