## Context

The tree's context menu is built once in `ProjectNavigator+Menu.swift` and
pruned per click in `menuNeedsUpdate` (`ProjectNavigator+Outline.swift`), which
hides what does not apply to the rows under the pointer — the compare items
over a folder, the diagram export over anything but a diagram, a session's
items off a session. Every row carries its git state: `FileNode.gitStatus`,
one of `unmodified`, `added`, `modified`, `deleted`, `unversioned`, `ignored`,
`conflicted`, with a folder taking the loudest of its children.

The Changes pane already discards. `discardClicked` in
`ChangesPane+Committing.swift` asks `discardable()` what the click is over —
paths, the changes under them, and a `GitDiscard.Subject` of one file, one
folder or several rows — puts up an alert worded by `GitDiscard.question`,
`explanation` and `buttonTitle`, and on the destructive button runs
`performDiscard`: the safety net's ref first (`DestructiveAsk.insureEstate`),
then `GitEstateOperation.discard` across every repository the paths fall in,
then the toast that says where the ref went. A conflict is never discarded;
untracked files are, and the wording counts them separately and says *delete*
when that is all there is.

None of that is reachable from a file in the tree. The tree can name the file,
its colour says it has changed, and the pane one tab away holds the verb.

## Decisions

### 1. The verb moves to the window, and both ask it

`performDiscard` and `discardable` stay the pane's for its own rows, but the
work they do — insure, discard across owners, say what happened — becomes
`MainWindowController.discard(paths:subject:)`, which the pane's `performDiscard`
calls and the tree's item calls. One rule for losing work, one ref made before
it, one toast afterwards. The estate is the window's, the same one the pane
reads from `submodules`.

*Ruled out: the tree calling into the pane.* The pane may not be open, and a
tree that shows the pane to borrow a method has changed the window to do a
thing the person asked of a row.

### 2. Discard in the menu, beside the other git verb

*Discard Changes*, worded by `GitDiscard.menuTitle` so a folder says how many
files and untracked-only says *delete*, placed after *Add to .gitignore…* and
before *Copy Relative Path*, in the group of things that talk to git about the
row. Hidden by `menuNeedsUpdate` unless the selected rows have something git
could discard: a file whose status is not `unmodified` or `ignored`, a folder
whose aggregate is not. A `conflicted` row hides it too, exactly as the pane
refuses one.

*Ruled out: under Compare*, though the report offered it. Compare is three
ways of looking, and an item that changes the file among three that do not is
the one somebody picks by mistake.

*Ruled out: leaving an untracked file to Move to Trash.* The proposal said so;
the pane already discards untracked files, its wording already says *delete*
for them, and a tree that answered the same word differently from the pane
beside it would be two rules again. The item follows the pane.

### 3. The same dialog, the same insurance

The alert is `GitDiscard`'s three sentences, as in the pane — they name the
folder and count what git has never seen, which no general dialog does — and
the ref is made before anything is restored. What the tree adds is nothing;
what it borrows is everything.

### 4. Afterwards

An editor tab open on the file reloads from disk, as it already does when a
file is rewritten outside the app — `reloadExternallyChangedFiles` on the
watcher's word. The tree's colour follows the same watcher. A compare tab open
on the file re-reads on the watcher too and shows no changes; that is the
compare page's existing behaviour and is measured here rather than built.

### 5. Driving

Two tree steps. `discard` opens nothing and prints the item's title and the
dialog's three sentences for the selected rows — what the pane's own driving
already prints for a row by name. `discard-confirm` performs the discard on the
run's scratch copy, which is the only checkout a run may touch, and prints
`git status --porcelain` of the file afterwards. A driven run is never on a real
checkout, by the house rule every run keeps.

## What was measured

*(the runs, once made)*

## Release note

> **A file's changes can be discarded from the tree.** Right-click a changed
> file or folder and *Discard Changes* puts it back the way the last commit had
> it — the same question, the same safety-net ref and the same toast the
> Changes pane gives, reached from the row you were looking at. An open editor
> tab reloads, and a compare tab on the file shows there is nothing left to
> compare.

## Open Questions

None.
