## Why

Reported 2026-09-04: *"we should keep more track of the UI status in the
session. For example: the git panel 'Working copy' section is always collapsed
when returning (and many more)."*

The example is exact. `BranchesPane.collapsedKeys` is seeded `["working"]` and
lives on the pane; `openedKeys` — the inverse set that keeps `origin` and `Tags`
open once somebody has opened them — lives there too. Nothing writes either of
them anywhere. The pane is thrown away and built again by
`SidebarController.install(tool:force:)`, so the folds do not merely die at quit:

- **at a project switch**, where the whole sidebar tool is rebuilt;
- **a second or two after a window opens**, when `readGit()` lands on a
  different work tree — the comment beside that code already names both halves
  of what it costs: *"it took with it the commit message half typed into the
  pane and the folders unfolded in it"*. The commit message half was fixed;
  the folders half was left;
- **when a tool shown over the terminal is put away**, because closing the
  popover reinstalls the tool with `force: true`.

So the working copy re-folds under somebody who unfolded it thirty seconds ago,
and there is nowhere it could have been written down.

It is not one pane. Every tree in the app records its folds the same way — in a
set on the view, restored across a rebuild and never further:

- the changes pane holds `Side.collapsed` per side and `Side.opened` for the
  untracked directories somebody opened by hand;
- the project tree computes `expandedPaths()` before each reload and puts it
  back after, and `load(project:)` resets it to the root alone;
- `currentSidebarTool` is a stored property defaulting to `.project`, so a
  window that lived in the git tool comes back on the file tree;
- the terminals come back — their names, their directories — and which one was
  in front does not, so four terminals come back showing the first.

The session already carries the expensive things: the tabs, the caret line, the
breakpoints, the half-written commit message, the pages. What it does not carry
is the shape somebody arranged the panes into, and that shape is re-made by hand
every morning. The refs tree's own sort orders are already remembered, for the
reason this change is about: *"this is a reading habit, and choosing again for
every checkout is choosing nothing."*

## What Changes

- **A tree's folds are part of the project's session.** The refs tree, the
  changes tree and the project tree each write down what somebody folded or
  unfolded, and come back that way.
- **The defaults are not overwritten by this.** The working copy still arrives
  shut, and `origin` and `Tags` still arrive shut, for a project nobody has
  folded anything in. Both sets travel — the negative one that says what was
  shut, and the positive one that says what was opened — because the asymmetry
  between them is load-bearing and flattening it to one list would lose it.
- **The folds are re-applied where a pane is built**, not once after a switch.
  A single application after `load(project:)` is undone a moment later by the
  rebuild `readGit()` causes, which is the lesson the composed message already
  paid for.
- **The sidebar tool that was in front comes back**, and falls back to the
  project tree where the remembered tool cannot be built — a folder in no
  working copy has no git tool. It does not open a sidebar somebody had closed:
  whether the sidebar is showing is the split view's autosave and stays there.
- **The terminal that was in front comes back in front**, by name rather than by
  index, and only where a terminal of that name came back at all.
- **A page named in a session that this version has an opener for is opened.**
  `sessions` already requires it — "the pages whose identity is their identifier
  alone" — and `reopen(page:)` has cases for `commit`, `log`, `stash` and
  `estate` only, so `launch` and `settings` are written into every session file
  and read by nothing. That is a requirement that exists and is unmet, not a new
  one.
- Nothing moves to `UserDefaults`. All of it is per project, in the file beside
  the project, because all of it is about *this* repository's branches, *this*
  project's folders and *this* project's terminals.

## Capabilities

### Modified Capabilities

- `sessions`: added requirements — a tree's folds are part of a project's
  session, the sidebar tool in front is, and so is the terminal in front.
- `git-refs-tree`: an added requirement — the tree's arrival defaults are for a
  project nothing has been recorded for, and a recorded fold outranks them.

### New Capabilities

<!-- none: this is the session's own account, widened again. -->

## Impact

- **AbydosKit**: `ProjectSession` gains three optional, additive fields — the
  folds, the sidebar tool, the terminal in front — read and written by
  `SessionStore` the way `reviewTicks` and `pages` already are; absent means
  nothing, so an older session file still reads. `filesOnly` drops all three:
  a folder in no working copy shares one session with every other such folder,
  and a fold keyed by a path relative to one of them means nothing in the next.
- **AbydosApp**: `BranchesPane` and `ChangesPane` gain a getter and a setter for
  their fold sets; `ProjectNavigatorViewController` gains one over
  `expandedPaths()`, which already exists and is already the right shape;
  `SidebarController` reads the session where it builds a pane, as it does for
  the commit message, and gains a case for `launch` and `settings` in
  `reopen(page:)`; `BottomPanel` records and restores which tab is in front;
  `MainWindowController` captures all of it where it captures the rest.
- **Driver**: unfold the working copy, switch away, switch back, and report the
  tree — the disk half cannot be driven at all, since a driven run deliberately
  reads and writes no session, so that half is a kit test on `SessionStore`.
