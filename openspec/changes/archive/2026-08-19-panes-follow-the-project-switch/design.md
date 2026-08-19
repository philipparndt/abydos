## Context

Two panes hold a project root taken at construction and are cached for the life
of the window.

`BacklogPane.init(projectRoot:)` builds `Backlog` and `OpenSpec` from it, decides
`hasBacklog` and `hasOpenSpec` from those, picks `source` from *those*, then
`build()`, `reload()`, `watch()`. All five of the first group are settled before
the pane has drawn anything, and `backlog` and `openSpec` are `let`.

`BottomPanel.showBacklog()` returns the session's existing pane and calls
`reload()` on it. `reload()` re-reads `backlog.projectRoot` — the old one.

`SearchPane` is the same shape, cached in `existingSearchPane` rather than in a
session because, as the comment there says, it also lives under the project view
or in a window of its own and so has no tab to be found by.

Panel sessions survive a project switch: `sessions.removeAll()` is in
`shutdown()`, called when the window closes.

There is already a pane that is told. In `load(project:)`:

    scratchesPane?.setProject(project.root)
    bottomPanel.setWorkingDirectory(project.root)

and `ScratchesPane.setProject` is four lines: bail if it is the same project,
take the new root, reload.

## Goals / Non-Goals

**Goals:**

- The backlog pane shows the project the window is showing, without being closed
  and reopened.
- The search pane never answers about a tree the window has left.
- A pane keeps its place in the tab strip: re-pointed, not rebuilt.
- What a pane worked out from the project at birth is worked out again.

**Non-Goals:**

- A protocol for project-bound panes. Two of them plus `ScratchesPane`'s
  existing method is a pattern; a mechanism wants a third.
- Rescoping panes when a **subproject** is entered. See the decision below —
  that is a different question and this change deliberately does not answer it.
- Remembering a pane's state per project, so switching back restores the query
  you had there. That is a session feature and a much larger one.
- The review, debug and profiler panes. They are bound to a run rather than to a
  project, and a run belongs to the project it was started in even after the
  window has moved on.

## Decisions

**The hook is `load(project:)` with `project.root`, not `setWorkingDirectory`.**
This is the decision with a trap under it. `setWorkingDirectory` looks like the
right seam — the panel already has it and it already means "this is the
directory now" — but it is called from *two* places with two different meanings:

    load(project:)  → bottomPanel.setWorkingDirectory(project.root)
    applyScope()    → bottomPanel.setWorkingDirectory(scope)

The second is entering a subproject. **A backlog is the repository's**, one
`.abydos/backlog` and one `openspec/` at the root, so a pane hung off
`setWorkingDirectory` would empty itself the moment somebody stepped into
`Sources/GoService` — a bug this change would have introduced while fixing
another. So the panes are told from `load(project:)`, on the line beside
`scratchesPane?.setProject`, and `setWorkingDirectory` keeps meaning what it
means for terminals.

Order matters and is already right: `applyScope()` for a restored subproject path
runs later inside `load(project:)`, so the panes are pointed at the root before
anything narrows the scope, and nothing narrows them afterwards.

**`init` splits so its tail can be run again.** Everything after `build()` —
rebuild `Backlog` and `OpenSpec`, re-ask `exists` for both, re-pick `source`,
`showContent()`, `reload()`, `watch()` — becomes one function that `init` calls
and `setProject` calls. Two code paths that must agree about what a project
means is exactly the shape that drifts; one function cannot.

**The watchers are stopped and dropped, not kept.** `watch()` guards with
`if watcher == nil`, so a pane that kept the old ones would be woken by a folder
in the project it left and never woken by the one it is in — a board that is
right when you open it and stale ten seconds later, which is worse than one that
is reliably stale. `deinit` already stops both; `setProject` does the same and
nils them so `watch()` will start new ones.

**`source` is re-picked, because it can become impossible.** The switch between
Backlog and OpenSpec is only shown where the project has both. Arriving at a
project with only `openspec/` while the pane is showing the backlog leaves it
showing a record that is not there — so the same rule `init` uses runs again:
backlog if there is one, else OpenSpec if there is one.

**The search pane's results are cleared, its query is not.** Results are file
paths in a tree the window has left; keeping them on screen is the fault, since
clicking one opens a file in the old project. The query is a person's words and
survives — it costs nothing to re-run and is the thing they would type again.

**A pane that has never been made is not made.** `showBacklog()` makes one on
demand and this does not change: switching projects with no backlog pane open
should not open one.

**Same-project switch does nothing**, the way `ScratchesPane.setProject` bails
on the same root. `switchProject` already returns early on the same path, but
`load(project:)` is reachable from more than one caller.

## Risks / Trade-offs

- **A watcher left on the old tree.** → The failure is silent and delayed, so it
  gets its own task and its own driven check: switch, then touch a file in the
  *old* project and confirm the board does not move.
- **Two panes fixed in one change, one of them unasked-for.** → Kept in its own
  section of the tasks so it can be dropped whole, and named in the proposal
  rather than slipped in.
- **`init`'s tail running again means running it against a project that has
  nothing.** A window can be switched to a directory with neither record. →
  That is the state the pane already has a view for (`BacklogAbsentView`), and
  `showContent()` is in the re-run for that reason.
- **The subproject question is now visible and unanswered.** Search arguably
  *should* narrow to the subproject, and today it keeps whatever root it was
  built with. → Named as an open question rather than settled here; this change
  makes the behaviour consistent (always the project root) instead of arbitrary
  (whatever was current when the pane was first opened).

## What the driven runs showed

**The fault itself, measured — and it was measurable after all.** The first
reading of this said the before-state could not be driven, because the verb that
reports it lives in the files the fix changes. That was wrong: the fix is *one
call*, so disabling only the call reproduces the pre-fix state exactly while the
report stays. With `BottomPanel.setProject` skipped:

    PANES before: window=proj-a  board=[project=proj-a backlog=true openspec=false items=143 changes=0]
    SWITCHED to proj-b
    PANES after:  window=proj-b  board=[project=proj-a backlog=true openspec=false items=143 changes=0]

The window moved and the board did not: still naming proj-a, still 143 of its
items, still answering `backlog=true openspec=false`, which are proj-a's answers
and not proj-b's. That is the report, in one line.

With the call in place, the same run:

    PANES after:  window=proj-b  board=[project=proj-b backlog=false openspec=true items=0 changes=2]

The temporary switch was removed afterwards; it exists nowhere in the tree.


Two scratchpad projects — one with a backlog and no `openspec/`, one with
`openspec/` and no backlog — switched with `--switch-project`, which follows the
terminal, and is the reported gesture.

    PANES before: window=proj-a board=[project=proj-a backlog=true  openspec=false items=143 changes=0]
    SWITCHED to proj-b
    PANES after:  window=proj-b board=[project=proj-b backlog=false openspec=true  items=0   changes=2]

and back the other way, to the same effect. The pane names the project it is
reading, the `backlog`/`openspec` answers are re-asked, and the counts follow —
so the switch between the two records appears and disappears with them.

**The half that fails silently, which is the one worth the trouble.** After the
switch, an item is written into the project that was *left*:

    PANES watch: wrote an item into proj-a
    PANES after touching the old project:
      window=proj-b board=[project=proj-b backlog=false openspec=true items=0 changes=2]

The board does not move. A watcher kept on the old tree would have reloaded here
and shown proj-a's work in a window on proj-b — right when opened and wrong a
moment later, which is harder to notice than being wrong throughout.

**That check was wrong twice before it was right**, and both times it was the
harness. It first reported `proj-b has no backlog to touch`: the old root was
captured *after* the switch, so it named the project just arrived at and touched
the wrong tree. A report that said only "watcher: ok" would have hidden it; one
that names the project it wrote into could not.

**A project with neither record:**

    PANES after: window=proj-none board=[project=proj-none backlog=false openspec=false items=0 changes=0]

Both answers re-asked, both false, which is the state the pane has a view for.

**And a pane nobody opened is not opened by switching:**

    PANES before: window=proj-a board=[no pane]
    PANES after:  window=proj-b board=[no pane]

**A verb already existed, and mine was dead code.** `--switch-project
path@seconds` has been there all along — it is how the terminal-follows-project
case is driven — and a second `case "--switch-project"` added to the same
`switch` never ran. The first run reported `SWITCHED to proj-b at 5s`, which is
the *old* handler's line, and it would have been taken for a pass if the format
had been closer. What was actually missing was not the switching but the
*report*: nothing said what the panes held afterwards. That is what was added.

## What was ruled out

Written while doing it.

**Hanging this off `setWorkingDirectory`, which is the obvious seam and is
wrong.** The panel already has it, it already means "this is the directory now",
and it is called from two places with two different meanings: `load(project:)`
passes `project.root`, and `applyScope()` passes the *subproject* scope. A
backlog is the repository's — one `.abydos/backlog`, one `openspec/`, both at the
top — so a pane told through that seam would empty its board the moment somebody
stepped into `Sources/GoService`. A bug introduced by the fix for another. The
panes are told from `load(project:)` instead, and `setWorkingDirectory` goes on
meaning what it means for terminals.

**Rebuilding the panes on switch.** It would work and it would lose the tab's
place in the strip, which is an arrangement somebody made. Re-pointing keeps it.

**A dictionary of panes keyed by project on the panel.** The state would then
need pruning when a project is closed by somebody remembering to; state that
lives on the thing it describes goes when the thing goes.

**A protocol for project-bound panes.** Two of them, plus `ScratchesPane`'s
existing `setProject`, is a pattern. A third is the moment for a mechanism.

**Keeping the search pane's results and letting the query re-run.** A result is a
path into the tree the window has left, and a stale one still opens — which is
the whole reason the search half was included. They are cleared; the query, being
a person's words, stays.

**Making `setProject` reload unconditionally.** Same root does nothing, the way
`ScratchesPane.setProject` bails: `load(project:)` is reachable from more than
one caller, and a board that flickers on every call is a board somebody stops
trusting.

## Open Questions

- Should the search pane scope to the subproject when one is entered? There is
  an argument either way — a subproject is where the work is, and a repository
  is what somebody means by "search this project". Today's answer is neither;
  it is whatever happened to be current when the pane was made.
- Should the backlog pane offer the *previous* project's board for a moment
  after switching — the way an editor keeps its tabs — rather than swapping
  immediately? Almost certainly not, but the terminal-follows-project case makes
  switches frequent and cheap, and frequent swaps of a board somebody is reading
  may turn out to be annoying in a way this cannot predict.
- The tab is titled "Backlog" with no project in it. With switching this easy, a
  strip showing which project a pane is about may be wanted — but that is every
  pane's question, not this one's.
