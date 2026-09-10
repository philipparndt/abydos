## Context

The navigator is one `NSOutlineView` with three roots — the files, the
Dependencies section and Claude Sessions — and it is rebuilt with
`reloadData()` in six places: a watched directory changing, a settings change,
the reload when the window comes forward or a language server edits files, the
sessions being read again, the Dependencies section being rebuilt, and the
redraw after a rename or a trash re-reads the rows' parents. Each of
those remembers which rows were expanded and which selected, reloads, and puts
both back, because `reloadData()` throws every row's state away.

None of them remembers where the list was scrolled. `reloadData()` collapses
every item, so for a moment the tree is a handful of rows and the clip view,
which cannot scroll past the end of a short document, is pulled to the top.
`restore(expandedPaths:)` then re-expands everything, the document is long
again, and the scroll stays where the collapse left it: at the top.

The sessions root is where this is felt, because it is the root that is rebuilt
while somebody is reading it. A running Claude session reports through the hook
on every event that changes which sessions are running or ends a turn, and a
session taking screenshots ends a turn every few seconds; each one reaches
`refreshSessions`, and when the read differs from what is shown — liveness
included — it goes through `show(_:)`, which is one of the six.

## Decisions

**Remember the top visible row, not a pixel.** The place is the identity of the
row at the top of the clip view — a file's path, `dep:` plus a dependency's
identity, `session:` plus a session's, the same keys `expandedPaths()` uses —
and its offset within that row. After the reload and the re-expansion, the row
is found again by its key and the clip view is scrolled so it sits where it
sat. A pixel offset would survive a rebuild that changed nothing and drift by a
row for every row inserted or removed above the reader, which is exactly what a
session starting does. When the row is gone, the pixel offset is the fallback,
clamped to the new document.

**In every one of the six, by the same two lines.** `rememberPlace()` beside
`expandedPaths()`, `restore(place:)` after `restoreSelection`, so a seventh
reload written later has a pattern to copy. `load(project:)` and
`setSubproject` are not among them: they are the tree becoming a different tree,
and the top is the right place to be.

*Ruled out: not reloading.* The paths that can avoid `reloadData()` already do
(`redrawVisibleRows()` for git colours, the identity comparison in
`refreshSessions` for a read that changed nothing). The rebuilds that remain
change the tree's shape, and an outline view rebuilds shape by reloading.

*Ruled out: `scrollRowToVisible` on the old top row.* It does the least it can,
and a row already partly on screen moves nothing, so the offset within the row
would be lost and the tree would settle a few pixels off each time — a
different jitter in place of a jump.

**Measured by two tree steps.** `end` scrolls the tree to its last row and
`place` prints where it is: the clip's offset, the top row's key, and the
first and last visible rows. A run scrolls, reloads, and prints twice; the
two lines are the claim.

## What was measured, 2026-09-09

**The jump did not reproduce in any rebuild a driven run can trigger.** A tree
of 122 rows in a pane showing 30, scrolled to its end with `end`, read with
`place` before and after each of these, all before the fix:

| Rebuild | Trigger | Place before | Place after |
|---|---|---|---|
| file tree reload (`reloadTreeMarked`) | the `reload` step | `y=2237 top=dir092 offset=19` | the same |
| watched directory | a file created from outside at 6.5 s | `y=2237 top=dir092` | the same |
| open file rewritten | the file in the editor appended to from outside | `y=2813 top=dir116` | the same |
| sessions root rebuilt (`show(_:)`), root collapsed | `--claude-running` event adding a session | `y=2261 top=dir093` | the same, one row more |
| sessions root rebuilt, root expanded by keyboard | a second event adding a second session | `y=2285 top=dir094` | the same, one row more |
| selection restored out of view | a row near the top selected, tree scrolled to the end, `reload` | `y=2237` | the same |

So the mechanism the proposal read from the code — `reloadData()` collapsing
everything and the clip view clamping to the top before the expansion is put
back — does not happen: the collapse and the re-expansion are in one turn, and
AppKit lays out once, after both. Restoring the selection does not scroll
either.

**What could not be driven.** A session's *files* changing while its folder is
open in the tree: the reporter is reading exactly those rows while the session
writes screenshots into that folder, and every such write changes the
session's `identityForRefresh` and rebuilds the root. In a driven run the
session's file rows never appeared under its row — the run declines transcript
reads and the measured walk did not fill them — so that path is measured by
nobody yet. The reveals were checked by reading: every `pendingReveal` is set
by a move, a paste or an undo, none by a background write.

**Applied anyway, and why that is not the plausible-fix trap.** Keeping the
top row across a rebuild is what the requirement says, it is two lines at each
site, and the runs above show it is a no-op wherever the place was already
kept — the after-numbers below are the before-numbers. It cannot make the
reported case worse, and it fixes the one class of jump a rebuild can produce
by construction: a document that is shorter for a moment. Whether that class is
the reporter's is the open question, and the answer needs their two facts.

*After the fix, the same runs:* the file-tree reload prints `y=2237 top=dir092
offset=19` twice, and the session event `y=2285 top=dir094 offset=19` twice
with a row added below — the before-numbers to the pixel.

## What was measured, 2026-09-10

**The reported case, driven.** The reporter answered the two questions below:
they were in the session's scratchpad folder, and the jump came, as far as they
remember, while opening a file — so it might have been the tree following the
editor. Both were driven.

What had blocked it was simple once read: a driven run declines *transcripts*,
not sessions. `AgentSessions.sessions` still scans `/tmp/claude-<uid>/<slug>/`
for session directories, so a session directory made for a scratch project —
`<id>/scratchpad/` with forty files in it — gives the tree a session row with
children, and `end` scrolls to them with the project's rows above out of view,
which is where the reporter was. A file is then written into that folder from
outside the app and `--claude-running <id>@7` fires the event a working session
fires, which is `claudeSessionsChanged` → `refreshSessions` → `show(_:)`. The
`place` step prints `rebuilds=` beside the position, because the first run of
this printed two agreeing lines over a tree the event had never reached.

| Run | Place before | Place after | Rebuilds |
|---|---|---|---|
| rebuild under the session's files, restore disabled | `y=3564 top=shot26 offset=2` | **`y=2508 top=dir104 offset=2`** | 2 → 4 |
| the same, restore in place | `y=3516 top=shot24 offset=2` | `y=3516 top=shot24 offset=2`, one row more | 2 → 4 |
| a session file opened from the tree (click, then ⌘↓), restore in place | `y=3540 top=shot25 offset=2` | the same, twice | 2 → 2 |

**That is the jump.** A thousand points up, from the session's folder to the
project's rows, on a rebuild the reporter did not cause — and the mechanism is
the one the proposal read from the code after all, in the one place the
2026-09-09 runs could not reach: `reloadData()` collapses everything, the
session's rows are at the *end* of the document, so the document is shorter
than the scroll offset for that moment and the clip view clamps to it at once.
The project's own rows survive the collapse, which is why a tree scrolled
among them never moved in the earlier runs.

**Opening moves nothing.** A single click previews and ⌘↓ opens; both reveal
the file in the tree, and `reveal` ends in `scrollRowToVisible`, which leaves a
row that is already on screen where it is. The reporter's memory of the jump
arriving while opening is most likely a session event landing in the same
second — with screenshots being taken, there was one every few seconds.

## Release note

> **The project view keeps its place.** Every rebuild of the tree — a session
> event, a file changing under a watched folder, a settings change, the reload
> when the window comes forward — now puts the scroll back on the row that was
> at the top, at the same offset, beside the expansion and selection it already
> kept. Reported as the tree scrolling up while a session's screenshots were
> being read; the rebuilds a driven run can trigger did not move it, so if it
> still does, say which rows were on screen.

## Asked of the reporter, and answered 2026-09-10

- Which rows are on screen when it jumps: the session's own files, or the
  project's? — *The session's scratchpad folder.*
- Is the screenshot being watched open in the editor, and does the jump come
  with a new file appearing in the tree? — *It jumped while opening, as far as
  they remember; and they do not see jumps any more.* Both are consistent with
  the table above: a rebuild while the session's files are on screen, which the
  fix stops, and not the opening itself.

## Open Questions

None.
