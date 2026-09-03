## Context

Eight outline views, four of them the ones people use all day. Each holds its
selection by path, restores it after a rebuild, and answers the arrow keys for
itself. `TreeSelection` was extracted when the *shrinking selection* fault was
found in more than one of them, and it answers one question: which paths are
selected, and which rows those paths are now. Everything around it was copied.

The immediate report is that → on a selected folder in the changes tree expands
it and loses the selection.

## Goals / Non-Goals

**Goals:**

- Expanding or collapsing a row never loses the selection, in any tree.
- One place that knows what a tree does with the keyboard and a rebuild.
- A restore that cannot find its row is *noticed*, not swallowed.

**Non-Goals:**

- Changing what any arrow key does. This is extraction and one fix, not a
  redesign of the keyboard.
- The four occasional outlines: settings, the debugger's variables, the
  structure pane, the variable popup.
- Replacing `NSOutlineView`. The behaviour is extracted around it.

## What it actually was

**The compaction hypothesis was wrong.** It fitted both screenshots and it was
not the mechanism. Naming it here rather than quietly replacing it, because the
reason it was written down as a hypothesis was so that this could be checked.

The tree in the report is the commit page's own outline, not `ChangedFileList`
— two different trees, and the guess was aimed at the wrong one.

The row in the screenshot is an **untracked** folder, which is the whole of it.
`ChangesPane.outlineViewItemWillExpand` takes a special path for a directory
that git has not seen: it has to *list* the directory before it has children to
show. That listing is a `git` call, so it goes out asynchronously, and when it
comes back:

    current.fill(with: rows)
    self.refreshColumns(for: outline)
    outline.reloadData()          // ← the selection dies here
    outline.expandItem(current)

`reloadData()` on an outline view clears the selection, and nothing puts it
back. So expanding an untracked folder with → opens it correctly and leaves
nothing selected — which is precisely the before-and-after in the report, and
why it happens on a `U` row and not on a tracked one.

It is worse than one keypress. `refill` calls the same `fill` for **every** open
untracked directory on every rebuild, and the tree is rebuilt on every
filesystem event — so any repository with an untracked folder open has been
dropping the selection at a rate set by whatever is writing to disk.

**And the staging report is a different fault with the same shape.** There the
row genuinely stops existing — it moves from `Unstaged` to `Staged` — so a
restore *by path* correctly finds nothing, and then does nothing, because
`select(path:)` returns early on a path it cannot find. That is the silence the
proposal predicted, and it is the one thing the two reports share: a selection
that goes away with nobody saying so.

## Decisions

**Diagnose before extracting.** The first task is a driven run that reproduces
the report and names the mechanism. The leading hypothesis is that a compacted
folder row's path changes when the compaction changes, so a selection held by
path cannot be found afterwards — but a hypothesis is what it is, and the report
may turn out to be an async status refresh landing on the expand instead. The
extraction is worth doing either way; what it must *fix* depends on the answer.

*Ruled out: extracting first and fixing whatever the shared code turns out to
do.* A shared component built around an unexamined bug shares the bug with three
more panes.

**A selection is held by path, and paths were never the problem.** With the
mechanism known, the identity question below is answered and closed: a path is a
perfectly good handle, and in the expand case the path is still there — nothing
looked for it. What was missing is that *something has to put the selection
back after a reload*, every time, rather than at the call sites that remembered.

So the shared piece is a keeper: take the selection before the work, put it back
after, and where the row has genuinely gone, fall back to its nearest surviving
neighbour and say so.

**A failed restore is reported.** Whatever the mechanism, `select(path:)`
returning early on a path it cannot find is how this fault became invisible. In
the shared behaviour, a restore that finds nothing falls back to the nearest
surviving row — `TreeSelection.surviving` already computes exactly that for the
delete case — and says in the log that it did, so the next report of this shape
names itself.

*Ruled out: selecting row 0 on a failed restore.* That is worse than no
selection: it moves somebody to the top of a list they were reading the middle
of, and looks deliberate.

## Risks / Trade-offs

**Four panes' keyboard behaviour is four panes' worth of habit.** → One commit
per pane, each with a driven capture of the key behaviour before and after.

**The trees are not as alike as they look.** The branches tree's rows are refs
and its ← and → fold sections; the changes tree opens everything with `*` and
has no merges; the commit list folds a merge. → The shared piece is the
selection and the rebuild, which they genuinely share. Keys stay per-pane where
they differ, and the design says so rather than forcing one keymap.

## What was fixed on evidence, and what was fixed defensively

Worth separating, because they are not the same confidence.

**On evidence**: the expand and the staging reports, which turned out to be one
fault — `fill`'s asynchronous `reloadData()`, quoted above, running after the
rebuild had put the selection back. And the unthemed selection, which is simply
a tree that was never given a row view.

**Defensively**: the log page's detail list not taking the keyboard. The
mechanism was *not* isolated — an outline view takes first responder on a click
by default, and why this one does not was not chased. What was done is to say it
explicitly in `mouseDown`, which the commit page's two trees already do for
their own reasons. If something was stealing the responder, this wins because it
runs on the click; if nothing was, it is a line that costs nothing. A driven run
still owes the proof, and it is task 3.1's.

## The one that took three tries, and why

The staging report was fixed three times before it was fixed. Each layer was
real, and each hid the next.

**First**: `fill`'s asynchronous `reloadData()`, which cleared the selection
after the rebuild had restored it. Fixed with the keeper, and it fixed the
expand report — but staging still lost it.

**Second**: three code paths staged and only two of them recorded where the
selection should go, so the fallback the pane already computes was simply absent
for the context menu and the section button. Moved into `runAcrossOwners`, the
one funnel every row-moving operation passes through. Then the report came back
in a more precise form, which is what made it solvable: *it shortly blinks at
the right selection and is then refreshed again and cleared out* — and, a minute
later, *when unstaging the staged files seem to also get shortly the selection*.

**Third, and the actual cause**: `isRestoring` is a synchronous flag, and
`NSTableView` posts its selection-change notification on a later run-loop turn.
So a notification caused by the pane's *own* restore arrived after the flag had
been cleared, and was handled as though somebody had clicked. What that handler
does on a click is deselect the *other* list — so the unstaged list's restored
selection was wiped by the staged list's restore posting a moment afterwards.
The mirror of it is the second report, word for word.

`stopRestoring()` now clears the flag on the next turn instead of the next line.
A person cannot click in the same turn the restore ran in, so nothing real is
swallowed by waiting one.

**What this says about the change.** Three layers of one report, in one pane,
each written by somebody solving the layer above it. That is the case for the
behaviour living in one place rather than being re-derived per tree — and it is
also why the extraction is not finished by this change: the shared piece exists
and three trees still have their own copies of the parts around it.

## The two row views, and why there are still two

`ThemedRowView` — a full-bleed band — was found already in place with eight
users, written "the last time two lists in one window disagreed about what
selected looks like". So the drift this change is about had already been half
fixed once, in the other direction.

They are not merged. A band is right for a *list*: a dense run of records where
the band is the row. A pill is right for a *tree*, where a full-bleed band
swallows the indentation that says what is inside what, and where going quiet
without the keyboard matters because a tree is usually not the pane you are
typing in.

So the four trees are on `TreeRowView` and the commit list, the debugger's
variables, the breakpoint list, the pull-request list and the value popup stay
on `ThemedRowView`. That is a boundary with a reason, written at both classes,
rather than a job half done.

## What the sweep found, 2026-09-02

**The branches tree had written the first half for itself.** `rebuildRows`
remembered every selected key across `reloadData()` and put back whichever it
found — and a key that had gone, a branch just deleted or filtered away, left
nothing selected and nothing said. It is on `TreeSelectionKeeper` now, by key
rather than by path, since a ref is not a file. Four more bare `reloadData()`
calls — on push, on publish, while deleting, on a theme change — dropped the
selection outright and go through the same keeper.

**The pull-request file tree is the log page's file tree.** Both are
`ChangedFileList`, so one extraction covers the fourth tree and the log page.
It restored by path across a rebuild and not across the line counts landing a
moment later, which is the commit page's `--numstat` fault one pane over; and it
had no fallback for a path that had gone, so ticking off the selected file with
the done ones hidden left nothing selected. Both on the keeper.

**One instrument for the click-then-arrow claim.** `TreeKeys` clicks a row and
presses an arrow the way a person does, for all four trees. The log page's own
instrument had posted screen-coordinate clicks through the system event tap,
which go to whichever window is frontmost — in a driven run, the terminal the
run was started from — and it hung a run. The shared one queues the release on
the app's own event queue and hands the window the press, activates the app
first because a press on a window that is not key is swallowed as an activating
click, and says which view was under the point. Three trees reported the
keyboard in a `TerminalView` before that last part, which read as the trees
failing when the instrument was.

**2b.5, answered: every tree takes the keyboard on a click.** Driven on the
same day — changes tree, project tree, branches tree, the file list on the log
page: click a row, the tree has the keyboard, ↓ moves the selection, ← folds a
folder and → opens it with the selection kept, and a rebuild keeps it. None of
the four needed what the log page's list was given; that list keeps its explicit
`makeFirstResponder`, since the reason it once needed one was never isolated.

**4.1, the outlines left alone.** Four outlines are not on the keeper: the
settings window's list, the debugger's variables, the structure pane and the
variable popup. None rebuilds on a filesystem event, none has had a report, and
each would need its own idea of a path. The sweep is of the four trees people
use all day, and says so.

## Open Questions

Both of the original questions are answered above: the identity is the path, and
the report was not the compaction. What is left is smaller:

- Whether `reloadData()` is needed at all where `fill` uses it, or whether
  `reloadItem(_:reloadChildren:)` on the one node would do — which would keep
  the selection by itself and make the keeper a belt to that brace. Worth
  measuring rather than assuming, since the comment beside it says an opened
  untracked directory can widen the columns, and that is a whole-view concern.
