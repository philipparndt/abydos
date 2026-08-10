# 439. New files and folders are named in the tree, not in a dialog

Creating a file or a folder opens a modal and asks for a name. Renaming one does
not — it puts an editable field on the row, in place, where the name is going to
be. The two gestures are the same gesture with a different starting point, and
only one of them interrupts.

The modal is also the second one this week to be reached for where the app
already had an answer: 0438 is the devcontainer question doing it, and
`Toast.swift` states the rule outright — *nothing interrupts unless the user
asked a question*. Naming a new file is not a question the app is asking; it is
the user's own gesture, half-finished.

## What it should be

A new row appears where the file is about to be, with an editable field on it and
the keyboard already in it. Return commits, Escape abandons the row entirely, and
the name is checked as it is typed the way a rename is.

## Most of this exists and is not being used

`commitRename` is the whole machine, and it has already had every argument:

- `CentredFieldCell` — the field is drawn on the row rather than over it, and 0411
  is four separate faults' worth of getting that right (vertical centring, the
  text shrinking, the field's width against the tree's).
- `EntryName.problem(_:kind:showingHiddenFiles:)` — the name is refused before it
  reaches the disk, with a sentence, and the field *stays* so the name can be
  corrected rather than thrown away and retyped.
- The collision check, refusing rather than overwriting, which is the rule
  everywhere else now.
- `holdRebuildForRename()` / `deferredRebuild` — the watcher must not rebuild the
  tree out from under an open field, which is a fault that only shows when
  something else is writing to the project at the time.
- `pendingReveal` — the row is a different object after the rebuild, so the
  selection follows the path.

None of that is optional for a new file either, and none of it is in the dialog
path today. That is the argument for this item beyond taste: the modal route
does not benefit from any of the four faults already fixed in the other one.

## The differences worth thinking about

**There is no row yet.** Rename edits a row that exists; this has to put a
placeholder row in the right place and take it away again if the name is
abandoned. Where it goes: inside the selected folder, or beside the selected
file, which is what `destinationFolder(for:)` already answers for a drop.

**Escape has somewhere to go wrong.** Abandoning a rename leaves the old name;
abandoning a new file has to leave *nothing*, including no empty file on disk —
so the file must not be created until Return, which is the opposite order from
"create it, then rename it", and the tempting shortcut.

**"New" is a submenu of kinds.** `NewFileKinds` offers the kinds a project has,
so the chosen kind decides the extension the field starts with, and probably the
selected range within it: `main.py` with `main` selected, so typing replaces the
stem and keeps the extension. Rename does not have that problem and will need to
grow the same idea.

**A folder that is not expanded** has to open before its new child can be shown,
and the same is true for a new file in a collapsed folder.

## Worth deciding

Whether the placeholder row is sorted into place as the name is typed, or sits
at the end until it is committed. Sorting as you type moves the row under the
cursor while somebody is looking at it; leaving it at the end means it jumps once
on Return. The second is probably right, and it is a choice rather than an
oversight either way.
