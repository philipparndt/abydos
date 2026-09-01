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

**A selection is held by identity where a path is not stable.** If the run
confirms the compaction hypothesis, the fix is not to make `select(path:)`
louder — it is that a row a person selected has to be findable after a rebuild
that changed how rows are grouped. Which identity that is, is the open question
below.

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

## Open Questions

- What a stable row identity is for a compacted folder. A path is what people
  think of, and it is what is unstable; the node's object identity does not
  survive a rebuild either. Possibly the deepest *file* under the row, which
  exists in both arrangements. To be settled once the run has confirmed what is
  actually breaking.
- Whether the report is the compaction at all. Stated as the leading
  explanation, not as the cause.
