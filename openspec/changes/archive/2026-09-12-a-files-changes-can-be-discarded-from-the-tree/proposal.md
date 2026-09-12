## Why

The maintainer, 2026-09-10, with a screenshot of the project tree's context
menu open on a changed file: *"it should be possible to undo all changes in a
file using its context menu (maybe in compare as this is a git action?)"*. The
menu offers Blame, Open as Hex, Compare — Against Last Commit, History…, With… —
Open Terminal Here, Reveal in Finder, Copy Path and the rest, and nothing that
puts the file back the way the last commit had it.

The action exists, one pane over. The Changes pane discards a file's changes
(`ChangesPane+Committing.swift`, `discardClicked`), through `GitDiscard` for the
wording and `GitDestructive.discard` for the dialog that stands in front of
anything that can lose work. A file in the tree is the same file; the tree
simply has no way to ask. Somebody reading a diff of a file they have decided
against has to find that file again in another pane to throw the diff away.

There is no originating `.abydos/backlog` item: this comes from a direct
report, 2026-09-10.

## What Changes

- **Discard Changes in the tree's context menu**, for a tracked file with
  changes in the working copy, and for a folder as the sum of the changed
  files under it. Worded by `GitDiscard` as the Changes pane words it, and
  guarded by the same `GitDestructive.discard` dialog, remembering the same
  answer — one rule for losing work, not two.
- **Where in the menu.** Not under *Compare*, though the report suggests it:
  Compare is three ways of looking, and an item that changes the file among
  three that do not is the item somebody picks by mistake. Beside the other
  git verbs — with *Add to .gitignore* — and separated from the two above it.
  Decided in the design, with the menu's own order in view.
- **An untracked file is not discarded**, because git has nothing to put back;
  the menu says *Move to Trash* for that already, and the item is absent rather
  than disabled, the way the tree's other git items are absent off a
  repository.
- **What the file shows afterwards.** An editor tab open on the file reloads
  from disk as it does when a file is rewritten outside the app, the tree's
  colour follows the watcher, and a diff tab open on it says the file has no
  changes rather than showing a diff that is no longer true.

## Capabilities

### Modified Capabilities

- `git-changes-detail` or `project-view`, whichever the design places it in:
  what the tree's menu offers a changed file, and that the one rule for losing
  work stands in front of it.

## Impact

- **AbydosApp**: `ProjectNavigator+Menu.swift`, the item and its enabling;
  the discard itself through what the Changes pane already calls, moved to a
  place both can reach if it is not there already.
- **Driving**: the `menu` tree step already lists the items; a `discard` step
  on a changed file, refusing on a driven run as the compare page's apply does,
  and printing what the dialog would have said.
