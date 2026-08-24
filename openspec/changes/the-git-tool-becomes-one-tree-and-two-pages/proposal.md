## Why

**Git in this app is three tool windows, five lists and two search fields, and it
still cannot make a tag.** Commit (⌘2), Branches (⌘3) and History (⌘6) are three
of the six buttons on the rail, and `ToolWindowBar.build()` draws a separator
around them with a comment explaining that it is there so "the strip reads as
three things rather than six". A group that needs a fence to be understood is one
button.

The missing verbs are not missing git. They are missing a place to stand. Every
verb in this app lives on a context menu, every context menu belongs to a pane,
so a verb can only exist where some pane already draws a row for its object:

- `GitTags.recreate` moves a tag and force-pushes it — written, tested, good —
  so a tag can be *recreated* because tags have rows in `BranchesPane`. A tag
  cannot be *created*, because a new tag has no row to right-click.
- Fetch and pull act on the repository, and no pane draws the repository. There
  is no `fetch` and no `pull` anywhere in `Sources/AbydosKit/Git` — the app can
  send work and has never been able to bring any down.
- Revert, cherry-pick, reset and checkout-this-commit act on a commit.
  `HistoryPane.makeCommitMenu` offers two items: `Copy Commit Hash` and
  `Copy Subject`.
- A stash has a row, so it has verbs; but nothing draws what is *inside* one, so
  `applyStash` restores blind.

Where a pane does draw the object, the same rule makes the menus sprawl:
`New Worktree…` appears in three of the four shapes `BranchesPane.menuNeedsUpdate`
takes, `Change the Remote…` appears twice, and checking out a branch is offered
in four places — the branch row, double-click, the context menu, and
`BranchMenu`, which was written separately and orders by recency.

Reported by the author on 2026-08-23: the Git UI feels too complicated, does not
support all features such as creating tags, and takes three tool items. Branch
names do not fold on `/`; stash handling is thin; a tag cannot be pointed at a
branch without typing its name into a bare field.

No originating backlog item: the backlog was dropped on 2026-08-19.

## What Changes

- **One tool item, one tree.** ⌘2 opens a single outline: the working copy and
  what has changed in it, the stashes and what is in them, local branches, each
  remote, tags, worktrees. Anything holding files expands to them; anything that
  is a ref opens a page. **BREAKING** for anybody with ⌘3 or ⌘6 in their fingers:
  Structure and Scratches move up to ⌘3 and ⌘4.
- **Branch names fold on `/`.** `feature/tags` and `feature/stash-preview` sit
  under a `feature/` row. A folder holding one branch stays flat, and filtering
  flattens the tree to full names.
- **The log and the commit become one editor page in two tenses.** A graph needs
  width and a commit needs its diff beside it, which a 300 pt column cannot give.
  Both already hand their detail to the editor area — `editor.openDiff` and
  `editor.openCommitDiff` are wired up today — so the views follow.
- **Nothing destructive happens unasked, and nothing destroyed is
  unrecoverable.** Switching a branch over uncommitted work, discarding,
  resetting, rebasing, amending, deleting a branch and moving a tag each say what
  they will cost and leave a real branch under `backup/` before they run.
- **Pull exists, with a dialog worth having.** Remote and branch pickers, `Into:`
  stated, `Rebase instead of merge` and `Stash and reapply local changes` — both
  remembered, and both outranked by the repository's own `pull.rebase` when it is
  set.
- **Tags can be made, moved onto a branch, and deleted.** The recreate sheet's
  bare text field becomes a picker over the refs already loaded, with the target
  resolved beneath it through `GitTags.describe` before the button is pressed.
- **Stashes become legible.** See inside one before taking it back; be told
  whether it will apply before the working copy is touched; branch from one;
  stash the hunks that are selected.
- **A commit message can be drafted by Claude**, from what is staged and the last
  twenty subjects of this repository, into two fields that stay editable.

## Capabilities

### New Capabilities
- `git-safety`: what counts as destructive, what is asked before it, and the
  backup ref left behind so it can be undone.
- `git-remote-traffic`: fetch, pull, the pull dialog and where its defaults come
  from.
- `git-refs-tree`: the one sidebar outline — its sections, its branch-name
  folders, and what each row says without being opened.
- `git-pages`: the log tense and the commit tense of one editor page.
- `commit-message-drafts`: drafting a commit message with Claude from the staged
  diff.

### Modified Capabilities
- `version-control`: the commit view moves out of the sidebar into a page, so
  what it says about two lists, folder staging and the commit box is restated
  about the page; discard gains the backup ref; stash handling gains a preview,
  an apply check and branch-from-stash.
- `left-rail`: three git buttons become one, and Structure and Scratches move up.

## Impact

- `Sources/AbydosKit/Git`: new `GitBackup`, `GitFetch`, `GitPull`,
  `GitCommits` (revert, cherry-pick, reset); `GitTags` gains create and delete;
  `GitStash` gains files, diff, `wouldApply` and branch; `GitChangeTree`
  generalises from `GitChange` to a path and a payload so the refs tree, the
  changes tree and the project tree share one builder.
- `Sources/AbydosApp/Git`: `ChangesPane`, `BranchesPane` and `HistoryPane`
  (3,303 lines) become one tree and one page in two tenses.
- `Sources/AbydosApp/ToolWindowBar.swift` and `MainWindowController`: the rail
  loses a button and two shortcuts move.
- `Sources/AbydosApp/Settings`: how this project pulls, and how long backup refs
  are kept.
- Claude drafting reuses the terminal target's existing Claude integration and
  adds no dependency.
