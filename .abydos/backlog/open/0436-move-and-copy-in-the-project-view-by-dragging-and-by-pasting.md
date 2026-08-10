# 436. Move and copy in the project view, by dragging and by pasting

Rearranging a project means leaving it. A file goes to the wrong folder and the
only ways to put it right are Finder, or a terminal, or renaming it with a path
in the name — and the last one works, which is the tell: `FileManager.moveItem`
is already there, it is just only reachable by editing the name.

Two gestures, and everybody already knows both:

- **Drag a row onto a folder** to move it there; hold ⌥ to copy instead.
- **⌘C then ⌘V**, with ⌥⌘V to move rather than copy, the way Finder does it.

Multi-selection is already in the tree, so both take several rows at once.

## Half of this already exists, and the half that does is misleading

**Dragging *out* works.** `outlineView(_:pasteboardWriterForItem:)` hands back
the node's `NSURL`, so a row can be dragged onto the terminal or into another
app. What is missing is the other side — there is no `validateDrop` and no
`acceptDrop`, so nothing can be dropped *into* the tree, including from Finder.

**⌘C exists and does the wrong thing.** `copyToPasteboard` writes the paths as
one newline-joined string, under `.string` alone:

    NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)

That is right for pasting a path into a terminal, and it is the reason ⌘C in the
tree cannot be pasted in Finder, or anywhere else, as a *file*.

**⌘C can be both at once, and it costs nothing to keep what is there.** Measured
rather than assumed, because the obvious change is the wrong one:

| what is written | items | types on an item | `string(forType: .string)` | files read back |
|---|---|---|---|---|
| `writeObjects([NSURL])` — the obvious swap | 2 | `public.file-url` | **nil** | 2 |
| one `NSPasteboardItem` per file, `.fileURL` + POSIX path as `.string` | 2 | `public.file-url`, `public.utf8-plain-text` | `/…/Makefile\n/…/Package.swift` | 2 |

Two things fall out of that. **`NSURL` carries no string representation of its
own** — swapping the current code for `writeObjects` would make files pasteable
and silently destroy the terminal paste, which is the trap this row exists to
mark. And **AppKit joins the per-item strings with newlines by itself**, so
writing one item per file with both types reproduces today's ⌘C output exactly,
character for character, while also being a real file copy. Nothing has to be
chosen between and nothing has to be preserved by hand.

So the shape is: one item per selected file; `.fileURL` for Finder and for the
tree's own paste; `url.path` as `.string` for the terminal. `readObjects(forClasses:
[NSURL.self], options: [.urlReadingFileURLsOnly: true])` reads them back.

## What the existing code already answers

The rename path is the model, and it has been through the arguments once:

- **A name is checked before it is used** — `EntryName.problem(_:kind:showingHiddenFiles:)`.
- **A collision refuses rather than overwrites** — "…already exists here."
- **The tree is rebuilt by `FileSystemWatcher` afterwards**, so the node object
  is gone and the selection has to follow the *path*: `pendingReveal` is how
  rename survives its own success, and a drop has exactly the same problem.

## What it has to decide that rename did not

**Which way round a bare drag is.** Finder moves within a volume and copies
across one, with ⌥ forcing copy and ⌘ forcing move. Following that is probably
right, but it means a drag from a project on an external disk quietly does a
different thing from the same gesture at home, and the row has to say which
before the mouse comes up.

**Several files, several answers.** Twelve dropped where three collide is the
problem `exportDiagram`'s comment already states about four diagrams at once:
"there is nowhere to say four things". A per-file prompt is a wall of dialogs; a
whole-drop refusal throws away nine that were fine. This is the one design
question in the item, and it should be settled before anything is written.

**Dropping onto a file.** Onto a folder is clear. Onto a file most likely means
its enclosing folder, which is what an outline view's `NSOutlineViewDropOnItemIndex`
handling has to say explicitly rather than leave to chance.

**What must be refused outright.** A folder dropped into itself or into its own
descendant, which is how a tree gets eaten; and the project root going anywhere.
Both are cheap to check and expensive to have not checked.

## Deliberately not in this item

**Undo.** Moving a file is not undoable today by any route, and making one
gesture undoable and not the others is worse than neither. If it is wanted, it
is its own item covering trash and rename too.

**Dragging to reorder.** The tree is the file system's order, not a list — there
is nothing to reorder, and a drop between two rows means "into their folder",
not "here".
