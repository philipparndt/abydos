# 442. Undo for what happens to files, starting with the trash

Moving a file to the trash is already the recoverable kind of delete — nothing is
destroyed, and the Finder will put it back. What is missing is ⌘Z: the recovery
exists but the gesture for it is somebody else's application.

**Three items have now deferred this and one of them said how it has to arrive.**
0436, on drag and paste:

> **Undo.** Moving a file is not undoable today by any route, and making one
> gesture undoable and not the others is worse than neither. If it is wanted, it
> is its own item covering trash and rename too.

That is this item, and the warning is the important part. ⌘Z that works after a
delete and does nothing after a rename teaches somebody it cannot be trusted, and
an undo nobody trusts is not used — so the fact that trash is the easiest one is
not a reason to ship it alone.

## The family

Everything that moves or makes a file, all of it now reachable from the tree:

| gesture | undo |
|---|---|
| move to trash | move back from the trash |
| rename | rename back |
| move (drag, ⌥⌘V) | move back |
| copy, paste, duplicate | trash the copy |
| new file or folder (0439) | trash it |

Note the fourth row: undoing a *copy* is itself a destructive act, so it goes to
the trash rather than being unlinked. Undo must not be the one operation in the
app that deletes something outright.

## What is already there and being thrown away

`NSWorkspace.shared.recycle` answers with a dictionary of original URL to the
place in the trash it went. The call site discards it
(`ProjectNavigatorViewController.swift:1388`):

    NSWorkspace.shared.recycle(urls) { _, error in

That `_` is exactly what an undo needs, and there is nowhere else to get it:
the name in the trash is not derivable, because the trash renames on collision
and two files called `main.py` from different folders do not both keep the name.
Whatever else this item does, that dictionary has to be kept.

## Where it has to fit

**Two undo stacks, and focus decides which.** The editor's ⌘Z undoes typing, and
it must keep doing that — a ⌘Z aimed at a stray character that puts back a folder
somebody deliberately trashed ten minutes ago would be much worse than no undo.
`NSUndoManager` travels the responder chain, which is the mechanism for getting
this right, and getting it wrong is the main risk in the item.

**A file operation is not undoable for ever.** The trash can be emptied, the
destination can be occupied by something else by the time undo runs, the file can
be changed by a build. Each of those is a refusal with a sentence rather than a
silent failure or a guess — the same standard `FileTransfer`'s refusals already
meet.

## What this does *not* license

0436 decided that a collision skips rather than overwrites, and one of its
arguments was that there is no undo, so an overwrite could not be taken back.
That argument weakens here, and it should not be quietly treated as gone: undoing
an overwrite means having kept the overwritten file somewhere, which is a much
larger promise than moving a file back to where it came from. **The skip rule
stands until somebody argues it down on its own merits**, with this entry noting
that one of its four supports has moved.
