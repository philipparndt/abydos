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

| gesture | undo | seen working |
|---|---|---|
| move to trash | move back from the trash | yes |
| rename | rename back | yes |
| move (drag, ⌥⌘V) | move back | yes |
| copy, paste, duplicate | trash the copy | yes |
| new file or folder (0439) | trash it | yes |

Note the fourth row: undoing a *copy* is itself a destructive act, so it goes to
the trash rather than being unlinked. Undo must not be the one operation in the
app that deletes something outright.

## What it came to

`FileUndo`, in the kit rather than in the view controller, because the app
target has no test target — a wall three agents hit on the same day. Five
gestures reduce to two reversals: put what is now *here* back *there*, or send
this to the trash. An `Action` is a list of each, and `reverse` walks them
against an injected `exists` and `modified` and answers with what can happen and
whole sentences for what cannot. Eighteen tests, no window.

The load-bearing half was already there and being thrown away.
`NSWorkspace.shared.recycle` answers with a dictionary of original URL to the
place in the trash each file went, and the call site discarded it. That is what
made ⌘Z after a delete impossible rather than merely unwritten: the name in the
trash is not derivable, because the trash renames on collision and two files
called `main.py` from different folders do not both keep the name. It is kept
now, error or no error — `recycle` can refuse one file out of four and the other
three are still undoable.

## The two stacks, which was the risk

**Focus decides which, and nothing has to be told.** `undo:` is sent from the
Edit menu with no target, so AppKit walks the responder chain from the first
responder and stops at the first object answering to it. That is `CodeView` when
the keyboard is in the editor and `NavigatorOutlineView` when it is in the tree,
and neither pane is in the other's chain — they are siblings, not ancestors.
Watched with the harness printing who answered:

    focus=editor   chain=CodeView              — and the trashed file stayed trashed
    focus=tree     chain=NavigatorOutlineView  — and it came back

**There is deliberately no `undoManager` override to go with it, and that was
the trap.** An earlier draft had one, on the reasoning that anything asking the
chain for a manager while the tree has the keyboard should be told about the
tree's. But the rename field is a *subview of the outline view*, so its field
editor's chain runs straight through here, and `undoManager` is exactly the
property a text view asks for when it registers typing. Answering it with the
file stack would have made the two stacks one — the editor for a filename would
have piled its keystrokes onto the same list as the deletes. One door instead,
and the door is `undo(_:)`.

The door closes while a name is being edited, and it closes by saying *no* to
`responds(to:)` rather than by answering with a no-op. A no-op would swallow the
key, since `tryToPerform` asks whether the method exists and not what it does,
and typing in the rename field would have had no undo at all. Saying no makes
the tree transparent and the chain carries on:

    focus=rename-field  first=NSTextView  chain=NSWindow  — the file stayed trashed
    after Escape        first=Outline     chain=Outline   — and then it came back

A drop is the one gesture in the family that can land while the caret is in the
editor — a drag from the Finder — so a drop that arrived takes the keyboard.
Undo lives where the gesture happened.

## Refusals

Each is a sentence rather than a silent failure or a guess, and one message
however many files: ⌘Z is one gesture. Seen in the corner, on a rename undone
after something else had taken the old name from outside the app:

> **Nothing was put back** — “alpha.py” cannot go back: something else is there
> now.

The occupying file was untouched, which is the point. The kit pins down the
others: an emptied trash, said in the trash's own words and under the name the
file had rather than the one the trash gave it; a folder that has itself been
trashed since, which is an ordinary thing to do a minute after trashing a file
inside it; and a file written in since, which is only checked for the ones that
would be thrown away. That last one earns its keep — somebody makes a file,
writes in it, comes back to the tree and presses ⌘Z, and trashing what they just
wrote is exactly the behaviour that teaches people not to trust undo. A restore
needs no such check: moving a changed file home is still putting it where it
belongs.

## What this does *not* license

0436 decided that a collision skips rather than overwrites, and one of its
arguments was that there is no undo, so an overwrite could not be taken back.
That argument has now moved, and it should not be quietly treated as gone:
undoing an overwrite means having kept the overwritten file somewhere, which is
a much larger promise than moving a file back to where it came from. **The skip
rule stands until somebody argues it down on its own merits**, on the supports
it has left. Undo keeps the same rule inside itself — a restore onto an
occupied name refuses, because an undo that wrote over a file would want an undo
of its own.

## What is not done

**There is no redo.** Taking a gesture back registers nothing in its place, so
⇧⌘Z over the tree is left unanswered and carries on down the chain rather than
being swallowed by a menu item that could never do anything. Redoing a copy
means keeping the source it came from, which is a larger promise than this item
made.

**New File hands the keyboard to the editor**, because 0439 opens the file it
just made — a new file is made in order to write in it. So the ⌘Z that undoes a
creation wants the tree focused first, where the other four leave it focused
already. The rule is the same one everywhere (focus decides which stack), but
this is the one gesture that moves the focus as part of what it does, and it is
worth knowing before somebody reports it as the family being uneven.

**The trash itself was not looked at.** That the copies and new files go to the
trash rather than being unlinked is the `recycle` call rather than an
observation: `~/.Trash` is not readable from the shell these agents run in. What
was observed is that they left the project, and that a trash restored from that
map comes back under the right name in the right folder.

**A run opened the wrong project, once.** With `--open` naming the fixture, one
launch came up on a project from the recent list instead and the script renamed
a file in it — put back by the undo under test, verified by mtime and by `git
status`, so nothing was lost. Not diagnosed and not reachable from anything in
this item, but anybody driving the app over destructive tree scripts should
guard on a listing first, as `collide.sh` ended up doing. It is worth an item if
it happens again.
