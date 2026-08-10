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

*The survey as it stood before the work, kept in the present tense it was
written in. What became of each part is in "What it came to" at the end.*

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

## What it had to decide that rename did not

Each of these is now answered, and each answer is written in the code beside the
thing it governs — so a decision somebody disagrees with can be overruled by
arguing with a comment rather than by guessing why it went that way.

### Several files, several answers — the one design question

**The ones that can go, go; the ones that collide stay exactly where they were;
and the whole drop says so once.** Nothing is ever overwritten.
`FileTransfer.plan` sorts a drop into transfers, collisions, refusals and
no-ops, and `Plan.summary` turns everything that did not happen into one
sentence.

Twelve dropped where three collide moves nine and posts *“f2.swift”, “f5.swift”
and “f9.swift” already exist here. The other 9 were moved.* Past four names it
stops and counts — a toast naming twelve files is a toast nobody finishes.

Why, against the three alternatives:

- **A prompt each** is the wall of dialogs, and the same "there is nowhere to
  say four things" `exportDiagram`'s comment already states. It also destroys
  what makes a drag a drag: the gesture ends when the mouse comes up, not three
  dialogs later.
- **Refusing the whole drop** throws away nine that were fine because three were
  not, which is the failure this item named.
- **Replacing** was never available. There is no undo here — deliberately, and
  stated below — so an overwrite cannot be taken back, and `commitRename`
  already answers a collision by refusing. Skipping keeps one rule everywhere
  instead of "a collision never overwrites, except when dragged".
- **The Finder's Keep Both**, renaming the newcomer, was considered and left
  out: it makes a file nobody asked for under a name nobody chose, and after a
  twelve-file drop there is no telling which of the two is which.

The cost, stated plainly: a drop can now half-succeed, and the only thing saying
so is a toast that can be missed. That is the price of not throwing the nine
away, and it is paid in a message rather than in lost work.

### Which way round a bare drag is

**A drag that starts in the tree moves, wherever it lands; ⌥ copies. A drag that
arrives from another application always copies, and ⌘ does not turn it into a
move.**

The Finder's rule — move within a volume, copy across one — was the obvious
answer and is deliberately not followed for drags inside the tree. The Finder's
window names the volume every file is on; this one does not. A folder inside a
project can be a mount point or a symlink onto another disk with nothing in the
tree saying so, and a gesture that silently changes meaning on information the
window never shows is a gesture nobody can predict. Inside one project the tree
is one thing, so the drag means one thing.

Nothing in the implementation wanted the distinction either: `FileManager.moveItem`
already does copy-then-remove when the two ends are on different volumes. **Not
proved here against a real pair of volumes** — the claim is Apple's, not a
measurement of this code.

Arriving from outside is the other way round, and there the Finder is plainly
right. An import that emptied the USB stick it came from would be a way to lose
files, and the tree cannot even show what it took them from.

### Dropping onto a file, and between two rows

Both mean **the folder holding them**. `validateDrop` retargets the highlight
with `setDropItem(folder, dropChildIndex: NSOutlineViewDropOnItemIndex)`, so the
row that lights up is the folder the files will really land in — what is about
to happen is visible before the mouse comes up rather than explained after.

### What is refused outright

The project root going anywhere, and a folder dropped into itself or into its
own descendant. Each has its own sentence rather than a shared one, because
"“p” cannot go inside itself" is a confusing way to say "that is the project".
The descendant test compares against `source.path + "/"`, so `/p/Sources` is not
treated as living inside `/p/Source`.

`validateDrop` works the whole plan out and throws it away, which is what makes
a drag that could only refuse show the "no" cursor instead of accepting and then
posting a toast. It costs a few string comparisons and one `fileExists` per
dragged file per mouse-move over a row.

## Deliberately not in this item

**Undo.** Moving a file is not undoable today by any route, and making one
gesture undoable and not the others is worse than neither. If it is wanted, it
is its own item covering trash and rename too. This is load-bearing above: it is
why a collision skips rather than replaces.

**Dragging to reorder.** The tree is the file system's order, not a list — there
is nothing to reorder, and a drop between two rows means "into their folder",
not "here".

**Duplicating.** ⌥-dragging a file onto its own folder is the one gesture that
reads as "make me a second one", and it collides with itself and says so rather
than inventing `a copy.swift`.

## What it came to

Three commits, and the shape of it is that everything deciding anything is in
`AbydosKit`, where it can be tested without a window — the reason `EntryName` is
there.

**`FilePasteboard`** writes one `NSPasteboardItem` per file carrying `.fileURL`
and the POSIX path as `.string`, and reads a board back with
`readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])`.
**Both rows of the table above are now tests rather than a paragraph**, including
the failing one: `theObviousSwapLosesTheTextEntirely` writes
`writeObjects([NSURL])` and asserts `string(forType: .string)` comes back nil.
On a scratch pasteboard named per test, so the suite never touches whatever the
person running it had copied a moment ago.

**`FileTransfer`** is the plan and the sentence. `exists` is injected the way
`TreeSelection` takes the tree, so twelve files colliding with three can be
asked about without a temporary directory.

**The navigator** gained `validateDrop` and `acceptDrop`; `⌘C` writing files as
well as paths; `⌘V` through the responder chain and `⌥⌘V` through
`handleKeyDown` — AppKit only dispatches key equivalents it finds in the *main*
menu, and the Edit menu's Paste is ⌘V alone. ⌥⌘V is matched on its character
rather than a key code: it is the only letter the tree binds, and a key code is
a position on an ANSI keyboard. All three keys are written down in the context
menu, which is the only place ⌥⌘V is written at all.

`pendingReveal` is a list now, for the reason the item predicted: a drop lands
several files at once and following one of them would be exactly the shrinking
selection `TreeSelection` exists to prevent. It is honoured as soon as *any* of
the paths appears, so a file that never arrives cannot hold the reveal open for
ever — **not proved against a partial arrival**, since nothing here can make one
happen on purpose.

### Driven end to end in the running app

Through `--tree`, on a scratch project, because a drop that works in a unit test
and not under the file-system watcher is a drop that does not work:

- Three files dropped on `Sources` where one name was taken: two moved, the
  third stayed, the toast read **"Not everything was moved"**, and the selection
  followed both survivors across the watcher's rebuild.
- `Folder` dropped onto `Folder/Sources`, and the project root dropped onto a
  folder: both refused, nothing on disk changed.
- ⌘C over two rows, then ⌘V into another folder: both copied, originals intact.
- ⌘C, then the ⌥⌘V *keystroke* rather than the method behind it: the folder
  moved.

1939 tests in 301 suites pass. `PlantUMLServerLiveTests` failed on one of four
full runs and passes under `make test FILTER=PlantUMLServerLiveTests` — the
load-dependent flake 0435 already documents, and not this work.

So this one is done, and moves to `completed`.
