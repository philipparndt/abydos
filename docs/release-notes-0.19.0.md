# Abydos 0.19.0

## Two files or two folders compare side by side

Any two files or folders on one page: both files beside each other, each
change joined by a curve, differing characters marked, *Change n of m* to walk
them, and the file's history down the edge so any two revisions can be A and
B. Folders align by path, hide equal rows, filter by name, and a row can be
marked to copy either way or delete; anything overwritten goes to the Trash
first. Opens from two selected tree rows, *Compare ▸ With…*, a file dropped
onto an open file, or `abydos-diff`, which also works as a git difftool.

## A card in progress lists its open tasks

Hover a card in the In progress column and its open tasks appear, each with a
box to tick in place. A task is ticked by its line, so identical lines under
different headings are distinct, and the file is re-read at the moment of
writing.

## A branch that is behind offers Pull or Fast-forward

The branch menu offers *Pull…* on the checked-out branch and *Fast-forward
to …* on a branch that is behind with nothing of its own. A branch whose
upstream is gone is offered neither.

## New File and New Folder are in the File menu

Both are in the File menu and the palette, not only the tree's right-click
menu. Asking from the menu bar brings the project tree back first.

## A file selected inside an archive stays selected

Clicking an entry inside a `.gz` or `.zip` in the tree no longer loses its
highlight on the next filesystem event.
