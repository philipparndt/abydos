# Abydos 0.19.0

## Two files or two folders compare side by side

Any two files, or any two folders, on one page: the whole of both files beside
each other with a curve joining each change to where it went, the characters
that differ marked, *Change n of m* to walk them, and the file's history down
the edge so any two revisions become A and B by clicking. On disk or at a
commit, either way round.

Two folders align by path — different, equal, only on one side, ignored — with
the equal rows hidden and counted, a filter over the names, and a row marked in
the gutter to copy one way or the other or to delete. What is marked is applied
together, and anything overwritten goes to the Trash first.

It opens from two selected rows of the tree, from *Compare ▸ With…*, from a file
dropped onto an open file, and from `abydos-diff`, which also works as a git
difftool. A page you had open comes back with the window.

## A card in progress offers its open tasks to tick

Half the tasks a change ends with are ones no test suite can prove, and what
proves them is somebody watching the app. That somebody was reading a card that
said `26/30` and then opening `tasks.md` to find the one line among thirty.

A card in the In progress column now lists its open tasks when the pointer rests
on it, and each one ticks where it is read. A task is ticked by the line it is
on rather than by its words, so three `- [ ] Tests` under three headings are
three different tasks, and the file is checked at the moment of writing in case
an agent rewrote it in between.

## A branch that is behind offers the verb that applies to it

Right-clicking `main ↓3` while standing on `main` offered Checkout, Merge into
Current, Rebase and Delete — every one of them greyed out against itself — and
nothing at all to catch up with. The row above said *3 behind* and had the Pull
button; the row that said the number had no verb.

The menu now offers *Pull…* on the branch that is checked out and
*Fast-forward to …* on a branch that is behind with nothing of its own on it,
which is the same distinction git makes: a ref you are not standing on can
simply be moved, and one you are standing on brings the working copy with it.

Pull is offered whether or not the counts say the branch is behind, because the
counts are as old as the last fetch and a pull is how you find out otherwise. A
branch whose upstream was deleted — the one left over from a merged pull request
— is offered neither, rather than a pull from a ref that is not there.

## New File and New Folder are in the File menu

Both have been in the tree's right-click menu since the tree could make files,
and nowhere else, so hands that go to the File menu first found New Window, Open
and nothing that makes a file. They are in the File menu now, and in the palette
with everything else the menus offer.

It is the same gesture: the row appears in the tree with its name selected on it
and nothing is written until Return. Asking from the menu bar brings the project
tree back on screen first, so it works with the sidebar showing git or closed
altogether, and both items are greyed out in a window with no project open.

## A file selected inside an archive stays selected

Opening a `.gz` or a `.zip` in the tree and clicking an entry inside it
highlighted the row until the next thing happened on disk, which under a project
being built is about a second. The tree rebuilds on every filesystem event and
puts the selection back by name afterwards — and it knew how to name a file row
and a session row, so an archive entry came back as nothing and the highlight
went out. An entry is now remembered the way an opened folder inside an archive
already was, by its path inside the archive.
