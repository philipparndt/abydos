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

- What makes it intermittent. Unanswered, and the first task.
