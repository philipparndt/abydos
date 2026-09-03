## Why

The rows in the running-sessions list jump around. Reported on 2026-09-03:
"the sort order in the claude integration popup is not stable, the items
jumping around."

Three separate things order by something that keeps changing, and the list is
rebuilt on every hook event *and* once a second by the staleness clock, so all
three fire constantly:

- **Groups after the first are ordered by recency.** `grouped` sorts the
  remaining projects by their most recent event, so a project's whole block
  moves up the list every time any session in it speaks — dozens of times a
  minute while anything is working.
- **Sessions with no tmux window are ordered by recency** within their group,
  for the same effect one level down.
- **Ties are not broken at all.** The records live in a dictionary, whose
  iteration order is arbitrary, and `sorted` is not stable — so two rows the
  comparison calls equal can swap on any reload without anything having
  happened.

Recency was a deliberate decision in the change that added the list, and it was
the wrong one: it is a sensible order for a list somebody reads once and a
hostile one for a list that redraws while they are reaching for it.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-03.

## What Changes

- **Groups are ordered by name**, after the window's own project, which stays
  first. A project's block does not move because a session in it spoke.
- **Sessions are ordered by where they are, not when they last spoke**: the
  tmux session's name, then the window's index, then the sessions with no
  window at all.
- **Every comparison ends in a tiebreak that cannot move** — the session's own
  id — so nothing reorders because a dictionary was walked in a different
  order.
- **REMOVED**: the recency ordering of groups, from the `running-sessions`
  requirement that stated it.

## Capabilities

### Modified Capabilities

- `running-sessions`: the popover's requirement loses "the rest SHALL follow
  with the most recently heard first" and gains an ordering that does not move
  while the list is open.

## Impact

- **AbydosKit**: `RunningSessions.grouped` — the two comparisons and the
  tiebreak. Tests for each of the three ways it moved.
- **AbydosApp**: nothing. The list draws whatever order it is handed.
- **Cost**: none; a sort of a dozen rows either way.
