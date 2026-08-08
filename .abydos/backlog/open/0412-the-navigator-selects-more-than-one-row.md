# 412. The navigator selects more than one row

The tree selects one row. Moving three files to the trash means doing it three
times, and dragging a handful out means dragging them one at a time.

`allowsMultipleSelection = false` is the line that turns it on, and it is the
smallest part of this. Everything else in the file asks `selectedRow` — one
row, one node — and each of those has to decide what it means for several.

## What each thing should do

- **Opening.** `outlineViewSelectionDidChange` shows the file the selection
  landed on, which is what makes arrowing through the tree feel like browsing.
  With more than one row selected it should show nothing new: a ⇧-click that
  opened four files would be a surprise, and the last one to open would not be
  the one under the pointer.
- **Rename** (in place, 0411) is a single-row gesture. With several selected it
  should be disabled rather than renaming whichever came first.
- **Trash** takes all of them. `NSWorkspace.recycle` already accepts an array,
  which is the one place this gets easier rather than harder.
- **Copy path** joins them with newlines, in the order they appear in the tree
  rather than the order they were clicked. `copyText` returns one string today.
- **Dragging** writes every selected URL. `pasteboardWriterForItem` is asked per
  item and already does the right thing — worth checking rather than assuming.
- **Open terminal here**, **open subproject**, **reveal**: single-row, like
  rename. `validateMenuItem` is where all of these get switched off, and it
  already exists for the row-versus-root cases.

## The part that will bite

The tree reloads on every filesystem event and puts the selection back
afterwards — `selectedPath()` and `restoreSelection(path:)`, both singular.
With several rows that becomes a set of paths, and a rebuild that keeps only
the first one is the kind of bug nobody reports precisely: the selection
quietly shrinks while a build writes files.

`selectionForTesting` already answers `(name, rows)`, so the harness can check
a multi-row selection survives a reload without anything new being added to it.

## Worth deciding

- **⌘A.** Select everything visible, or nothing? Everything *visible* is what a
  tree usually means, since the rest is not loaded.
- **What the status bar and the editor's "locate" do** when several rows are
  selected — probably nothing, but say so rather than leaving it.

---

Its number is where it sits in the queue, not what it is worth doing next.
