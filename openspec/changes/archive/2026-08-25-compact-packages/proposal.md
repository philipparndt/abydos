## Why

A Java project spends most of its tree on directories that hold nothing but one
other directory. `src/main/java/com/example/myapp` is five rows to reach the
first file, four of them a single folder with a single folder inside it, and the
pattern repeats in every module — so a reactor of fifty modules costs two
hundred rows of nothing before any code is visible. Scrolling past them is the
ordinary experience of opening a Java project in this tree.

Every IDE that people arrive here from folds these into one row. IDEA calls it
*Compact Middle Packages* and has had it on by default for years.

The tree is not otherwise wrong: the rows are real directories and each is one
click. What is wrong is that five rows say what one row could.

## What Changes

- A chain of directories where each holds exactly one entry and that entry is a
  directory SHALL be shown as a single row.
- Under a Java source root the components join with dots, so
  `com/example/myapp` reads `com.example.myapp`; everywhere else they join with
  slashes, so `src/main/java` reads as itself.
- A new toggle in the project view's header, beside Collapse All and the locate
  button, turns it on and off. It is remembered like the other view
  preferences.
- Expanding, selecting, revealing a file from the editor, renaming, the context
  menu and drag and drop all keep working on a folded row: it stands for the
  last directory in the chain, which is where its contents are.
- **Off by default.** The tree changes shape under this, and a change of shape
  that nobody asked for is one people have to undo before they can work.

## Capabilities

### New Capabilities
- `compact-packages`: which chains of directories are shown as one row, how that
  row is named, and the control that turns it on.

### Modified Capabilities

None. `openspec/specs/project-view` describes what the tree lists and how it
refreshes; it says nothing about folding, so this adds a capability rather than
changing one.

## Impact

- `FileNode` — the chain walk, and the name a folded row carries. Kit-side, so
  it is testable without a window.
- `ProjectNavigatorViewController` — the outline's children, and the four places
  that walk the tree by hand: expansion save and restore, reveal, and the
  watcher's reload.
- `NavigatorHeaderView` — a third button.
- `Settings` — one more boolean, alongside `showHiddenFiles`.

**The cost is the thing to watch.** Today a directory is listed when somebody
expands it. Deciding whether a directory is foldable means listing it *before*
it is expanded, once per visible directory — which in a tree of a quarter of a
million files is the sort of change that has taken the main thread for the
better part of a second before, and is why `reloadPreservingIdentity` is written
the way it is.
