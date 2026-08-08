# 411. Rename in place, with Return, the way the Finder does

Renaming a file means finding it in the context menu and answering a dialog
(`contextRename`, an `NSAlert` with a text field in it). Everybody who uses a
Mac already knows the other way: select the row, press Return, and the name
turns into a field with the stem selected.

Two things, and the second is the one that matters:

- **Return renames the selected row.** The navigator already takes keys —
  `keyDown` is overridden and there is a testing hook for it — so this is
  which key does what, and making sure Return does not still mean "open" where
  it used to.
- **The editing happens on the row.** Not a sheet in the middle of the window:
  the name is edited where the name is, so the surrounding files stay visible
  and it is obvious what is being renamed.

There is a precedent in this codebase to copy rather than invent: the terminal
tab strip renames in place already — double-clicking a tab puts an `NSTextField`
over it (`renameField` in `BottomPanel`), Return commits, Escape puts it back.
The same shape over an outline row is what this is.

## What has to keep working

`contextRename` is not just a prompt. It validates with `EntryName.problem`,
it moves the file, and it reports what went wrong in a toast. The in-place
editor has to do all of it, and the validation has to happen *before* the field
gives up focus, or a bad name is a rename that silently did not happen.

Worth deciding:

- **What is selected when the field appears.** The Finder selects the stem and
  leaves the extension alone, which is right nearly always and is the detail
  people notice when it is missing.
- **What follows the rename.** An open tab on that file, its position in the
  tree, the git status of the row, and the selection — the tree reloads on the
  filesystem event, so the row is a different object afterwards and the
  selection has to be restored by path, which `restoreSelection(path:)` does.
- **Where else Return should do this.** The changes pane lists files too. Same
  key, same expectation, and it can come later.

Escape cancels. A name that is unchanged is not a rename. An empty one is a
cancel rather than an error, since that is what the field being empty means.

---

Its number is where it sits in the queue, not what it is worth doing next.
