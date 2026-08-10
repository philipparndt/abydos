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

## Decided: it sits at the end of its folder until Return

The taste argument is the one above and it stands, but there is a mechanical one
that settles it. The field is not part of the row: it is a subview of the
outline view, given absolute coordinates over one row's rectangle. A row that
re-sorted itself on every keystroke would leave the field behind on whatever had
moved into those coordinates, so the field would have to be measured and placed
again on every character typed — the geometry 0411 needed four goes to get right
(vertical centring, the text's size, the right edge against the pane rather than
against the widest name), recomputed under a live caret and a live selection.
Sorting as you type buys nothing and pays that.

So the row appears last among its folder's children and stays there. It jumps
once, on Return, and `pendingReveal` is what makes the jump end with the row
selected and scrolled to rather than lost — which is the same machine the rename
and the drop already use for the same reason.

## What it came to

The dialogs are gone: `askForName` and the whole of the old `contextNewFolder`,
about eighty lines, and with them the second modal of the week. `New ▸ File`,
`New ▸ Folder` and every kind under them now put a row in the tree with a field
on it. All three lost their ellipsis, and so did `Rename`: an ellipsis promises
a dialog, and none of them opens one any more.

**One machine, not two.** `renameField`/`renaming` became `nameField` and an
`editing: NameEdit` — `.rename(node:original:)` or
`.create(placeholder:parent:kind:anchor:)`. `beginRename` and `beginNew` both
end in `beginEditing(_:row:name:)`, which is the whole of `CentredFieldCell` and
0411's geometry; Return goes to `commitName()`, which switches on the case;
Escape and everything else goes to `endEditing()`. `holdRebuildForRename()` and
`deferredRebuild` needed one word changed and cover both — and they matter more
for a new row than for a rename, because a rebuild asks the file system what is
in the folder and the placeholder is not in it.

**The placeholder** is an ordinary `FileNode` belonging to nothing on disk,
handed to the outline view by three lines in the data source:
`numberOfChildrenOfItem` adds one to its parent's count, `child(index:ofItem:)`
returns it for the index past the end, and `isItemExpandable` says no — a folder
that does not exist has nothing to list. `FileNode` itself is untouched.

**Nothing is written until Return.** `.create` holds no URL that has been
touched; `commitName` validates, then writes, in that order. Escape drops the
placeholder, rebuilds, and puts the selection back on the row the gesture
started from, which is what `anchor` is for.

**The name the field opens with** moved into `AbydosKit` as
`EntryName.draftName(kind:)` and `EntryName.stemLength(of:kind:)`, with tests.
The draft is the Finder's — `untitled`, `untitled folder`, and
`untitled.py` for a kind — so that New then Return makes something rather than
reporting that a name is required. `stemLength` selects the stem of a file and
the whole of a folder, so typing replaces the name and keeps the extension; a
dotfile is all stem, because `.gitignore` is not an entry of kind `gitignore`.
Rename uses the same function now, which is what the item guessed it would want.

`contextParentDirectory` was a copy of `destinationFolder(for:)` and is now a
call to it, so a new file and a drop land in the same place by the same rule.

### Two faults found by looking at it rather than by testing it

**The field was not drawn on a new row at all.** Everything readable as a number
was right — the frame, the row rectangle, the font, and the row correctly
stopping drawing its own name — and the pane showed an empty highlighted row.
An outline view builds its row views at the next layout pass, not when it is
told to reload, so the field went in first and the fresh row view was built over
it. `layoutSubtreeIfNeeded()` before the field goes on. Renaming never met this
because its row was already on screen.

**A refused name was reported twice.** `makeFirstResponder` on the field that is
already being edited is not a no-op: it tears the field editor down and builds
another, `controlTextDidEndEditing` arrives, and the name is committed, refused
and reported a second time. Two identical toasts stacked in the corner. Now the
keyboard is only taken back when the field has not got it. **This was already
true of a refused rename** and nobody had noticed; sharing the code is what
made it visible.

### Seen working, not only tested

Driven through `--tree` on a scratch project, and looked at:

- `New ▸ Python (.py)` on a file: the row appears at the end of that file's
  folder with `untitled.py` on it and **`untitled` selected, `.py` not** —
  photographed, not inferred.
- Typed into that selection, Return: `script.py` on disk, opened in the editor,
  the row jumped into sort order and stayed selected.
- On a **collapsed** `Docs`: the folder opened and `notes.txt` was made inside
  it.
- `New ▸ Folder` with nothing typed: `untitled folder` created.
- **Escape: `ls` of the folder and of the root are unchanged.** No empty file, no
  row left behind, selection back where it started.
- A colliding name and a name with a slash: the field stays with the name still
  in it, one toast, nothing on disk.
- `reload` — a watcher rebuild — while the field is up: the field survives with
  its text, and the rebuild happens when the field goes.
- ⌘⌫ while the field is up: it edits the field and trashes nothing.

The harness gained `new-begin:<kind>`, `new:<kind>:<name>` and `ls:<folder>`,
and `renameFieldReportForTesting` now also prints the name and the selected
substring — a one-line highlight is not something a screenshot proves. `new:`
types into the selection rather than assigning to the field, which is the
difference between asking what the app does and asking what the harness does: it
caught its own first version making a file called `script` instead of
`script.py`.

1997 tests in 309 suites pass, `PlantUMLServerLiveTests` included.

### Left standing

- **The icon on the placeholder row is chosen when the row appears and does not
  follow the extension as it is typed.** `untitled.py` shows the Python icon;
  typing `.md` over it leaves the Python icon until Return. Nobody has complained
  because nobody has had it yet.
- The placeholder's `FileNode` keeps the URL it was born with, so the tree's own
  bookkeeping calls the row `untitled` while the field says something else. It is
  never drawn — the field covers it — but it is what the harness reports as the
  selected row's name during an edit.
- **Not tried at a large zoom**, which is where three of 0411's four faults
  showed. The geometry is now literally the same code as the rename's, so it
  either has all four fixes or none, but that is an argument rather than a
  measurement.
- There is still no keyboard shortcut for New; it is a menu gesture only.

Done, and moved to `completed`.
