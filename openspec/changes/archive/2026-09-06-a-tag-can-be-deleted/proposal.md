## Why

**The engine has deleted tags since the day it learnt to move them, and
nothing in the app asks it to.** `GitTags.delete` and `GitTags.deleteOnRemote`
are both written, tested and called by nobody: the refs tree's tag rows offer
*Recreate* and the forge, and the only way to get rid of a tag is a terminal.
The spec says otherwise — *A tag can be made, moved onto a ref, and deleted* —
so what is written down is a promise the window does not keep.

It is the second half of the moving-tag work. Moving `v1` is
delete-and-rewrite in two places, which the app does in one sheet; getting rid
of a tag outright is the same two places and no sheet at all. And a tag is the
one ref this app can make from three different rows — a commit, a branch, the
tags section — so making one by mistake is easy and undoing it is a trip to
the command line.

Asked for on 2026-09-06: "it should be possible to delete tags (+ remote
tags)".

No originating backlog item: asked for directly.

## What Changes

- **A tag row offers to delete the tag**, one row or several selected, from
  the tags section of the refs tree and from wherever else a tag row appears —
  through the same menu that moves it, and reachable from the keyboard as
  every other row action is.
- **The sheet asks about the remote separately**, because the two deletions
  have different consequences: locally a tag is a file that can be written
  again from any commit that still exists; on the remote it is what a
  workflow, a release page and everybody else's `git fetch` reads. The remote
  is offered where the repository has one, off by default, and named — *Also
  delete on origin* — rather than implied.
- **What it is about to do is said before it is agreed to**: which tags, what
  each points at, and — for the remote half — that a running workflow reading
  that tag will stop finding it.
- **A failure says which half failed.** Deleting locally and failing on the
  remote is a real outcome (no permission, a protected tag, the network), and
  the sheet's report says the tag is gone here and still there.
- **Not proposed:** deleting a tag from the forge's release page, deleting
  branches (which has its own sheet and its own worktree consequences), or
  any change to how tags are made or moved.

## Capabilities

### New Capabilities

<!-- None: tags are already a capability of `version-control`, and the refs
tree is already `git-refs-tree`. This is a verb they both already describe
somebody being able to reach. -->

### Modified Capabilities

- `version-control`: *A tag can be made, moved onto a ref, and deleted* says
  deleting is possible and says nothing about how it is asked for. It gains
  the ask: what the sheet names, that the remote is a separate agreement, and
  what is said when one half of it fails.
- `git-refs-tree`: *A row's action can be reached from the keyboard* covers
  the tree's rows generally; the tag row's delete joins the verbs it names, so
  that the tags section is not the one place a row's own action is menu-only.

## Impact

- `Sources/AbydosApp/Git/BranchesPane.swift` — the tag row's menu gains the
  item, the selection rule (tags only, and all of them tags), and the call
  into the sheet. The pane already has `recreateTag` beside it as the shape to
  follow.
- `Sources/AbydosApp/Git/TagDeletion.swift` — new, and a sibling of
  `BranchDeletion` rather than a mode inside it: a branch delete is a question
  about worktrees and merged-ness, a tag delete is a question about the
  remote, and one type answering both would answer neither in its own words.
  It takes `BranchDeletion`'s one hard-won lesson with it — the object holds
  itself while its sheet is up, because `ask` returns the moment the sheet
  appears.
- `Sources/AbydosKit/Git/GitTags.swift` — nothing new: `delete` and
  `deleteOnRemote` are what this calls, and the ref is fully qualified for the
  reason already written there.
- No new dependency, no network call this app does not already make.
