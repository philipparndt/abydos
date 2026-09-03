## Context

`RunningSessions.grouped(firstSlugs:at:)` builds the list: the window's own
project's groups first, then the rest, each group's sessions ordered. It is
called by the popover on every reload, and the popover reloads whenever the
register moves and once a second while anything is working.

## Goals / Non-Goals

**Goals:**

- A row stays where it is for as long as the session it stands for exists.
- The order is total: no two rows can be called equal.

**Non-Goals:**

- Sorting the window's own project among the rest. It is first because it is
  the nearest, which is a different claim from alphabetical.
- Grouping by anything but the project. The filter is how somebody narrows the
  list; the order is how they find a row twice.

## Decisions

**Order by where a session is, never by when it spoke.** A tmux session's name,
then the window's index — both of which a session keeps for its whole life, and
both of which are what a person reads the row by. Sessions with no tmux window
come after the ones that have one, in id order.

*Ruled out: recency.* It is what the list shipped with and what the report is
about. A list that reorders while it is open cannot be clicked: the row under
the pointer is not the row that was under it when the hand started moving.

*Ruled out: keeping recency and freezing the order while the popover is open.*
Two orders for one list, and the frozen one would be wrong the moment the
popover is reopened. The order should simply not depend on time.

**Groups by name, not by slug.** The name is the last component of the project's
path, which is what the header shows — so the list reads in the order it is
written. The slug breaks the tie, since two projects can share a last
component.

**Every comparison ends in the id.** The records are a dictionary and `sorted`
is not stable, so any pair the comparison calls equal is free to swap on the
next reload. The id is unique and never changes. A seeded record has no id, so
the tmux session and window index it does have come first in its comparison and
the empty id is the last resort — two seeded records for one window cannot
exist, since the register keys them by window.

## Risks / Trade-offs

**A session that starts working is not brought to the top** → It was never
brought to the top; it was brought to wherever its project's last event put it,
which is not the same thing and is not what anybody could rely on. The pill
says whether anything is working, and the filter finds a project by name.

**Two projects with the same last path component sit adjacent in an order the
name does not explain** → The slug breaks the tie, and the header shows each
one's parent directory, which is what tells them apart.
