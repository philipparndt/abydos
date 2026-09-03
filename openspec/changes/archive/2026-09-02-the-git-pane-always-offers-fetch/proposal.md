## Why

The git pane's repository row draws one verb chosen from the repository's state
— `Fetch` when level, `Pull` when behind, `Push` when ahead — so `Fetch` is the
one verb that disappears exactly when somebody wants it. A branch one commit
ahead offers `Push`, and the question "has anybody else pushed?" has no button
at all.

There is a glyph beside that verb, added in 0.10.0, and it already fetches: its
own comment says re-reading was local only and the pane re-reads on every
filesystem event anyway, so a press was only ever for something that happened
elsewhere, and the largest elsewhere is the remote. But it is a pair of sync
arrows with the word `Fetch` in a tooltip, and a tooltip is not a label. It was
asked for again on 2026-09-01 as a missing button — the same way drafting a
commit message was asked for while it existed, and for the same reason: a verb
nobody can read is a verb nobody has.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-01 — "I always want a fetch button in the git pane. Maybe the
Refresh button can be replaced and we always have the Fetch button instead."

## What Changes

- The glyph beside the traffic verb is replaced by a control that says
  **`Fetch`**, in words, always shown where the repository has a remote. It does
  what the glyph already did.
- **REMOVED**: the refresh glyph and the local re-read it offered where there is
  no remote. A repository with no remote has nothing to fetch, so the control is
  not drawn there at all; re-reading stays on the row's context menu, which
  already carries every verb the remote allows.
- The state-chosen verb is unchanged: `Pull` when behind, `Push` when ahead,
  `Fetch` when level. Two `Fetch`es side by side when level is not a mistake to
  fix here — the row's verb is what ⌘⏎ fires and the new control is a second
  target for the same act — but the design says what is done about it.

## Capabilities

### Modified Capabilities

- `git-remote-traffic`: gains a requirement that fetching is reachable in one
  press whatever the repository's state, and loses nothing — no existing
  requirement states that re-reading is a control of its own.

## Impact

- **AbydosApp**: `BranchesPane`'s `secondaryAction` becomes a titled action
  rather than a symbol one, and `refreshPressed()` loses the no-remote branch it
  guards with; `RowAction` already carries a title, so nothing new is needed
  there. `pressRefreshGlyphForTesting` is renamed for what it now presses.
- **Driver**: the row's controls are already readable; the driven claim is that
  `Fetch` is present with the branch one ahead, which is the state that used to
  hide it.
- **Cost**: none. The same call, said out loud.
- **Depends on** `the-zoom-reaches-every-control` for the control it is drawn
  with, and should land after it so the new verb is not born unscaled.
