## Context

The project tree's context menu is built in `ProjectNavigatorViewController` (one `NSMenu`, delegate-driven, an `item(_:_:)` helper, per-row hiding in `menuNeedsUpdate`). The diff tab opens through the sidebar's `showDiff` plumbing over `GitWorkingCopy` diffs rendered by `DiffView`. The log page (`HistoryPane`) scopes to a file — `offeredPath`, `setScope(path:)`, the "Whole Repository | This File" control — with `GitHistory.log(path:)` running `--follow`. A commit row on the log page already has a menu (`commitMenuForTesting` reads it). Nothing connects a file row to any of it.

## Goals / Non-Goals

**Goals:**

- Compare ▸ Against Last Commit and Compare ▸ History… on a file row, each
  landing on the existing surface.
- Compare with Working Copy on a commit of a file-scoped log.
- The submenu tells the truth per row: absent or disabled where there is
  nothing to compare, following the row's existing menu discipline.

**Non-Goals:**

- No new diff renderer and no side-by-side version picker: the log page *is*
  the version picker, and `DiffView` is the renderer. A two-arbitrary-versions
  compare (v3 against v7) is not asked for; every offered comparison has the
  working copy or HEAD as one side.
- No compare across files or folders; a folder's history is the log page's
  own question if it ever gets asked.
- No editor-tab context menu changes in this change: the tree is where the
  request points; the tab menu can copy the pattern later if wanted.

## Decisions

### Against Last Commit is the HEAD diff, staged and unstaged together

The same question the editor's change marks answer — what have I changed
since the last commit — so the same diff: `diffAgainstHead`, not the
working-vs-index diff the changes tree shows per side. Ruled out: opening the
changes-tree diff for the file — it splits one question across two sides and
fails entirely for a file whose change is fully staged.

### History… opens the page the "This File" segment already reaches

`showLogPage` plus the pane's file scope, with the scope control showing
"This File" selected — one page, arrived at from a second door, so the spec's
one-page rule for logs holds. Ruled out: a popover listing versions — it
would be a second, poorer log.

### Compare with Working Copy is one git argument

`git diff <hash> -- <path>` is the working copy against that commit, in the
unified form `GitPatch` and `DiffView` already speak. Offered only on a
path-scoped log: on the whole-repository log the "working copy against then"
question spans every file, which is not a diff tab, and the menu item would
be a lie about what it opens. Ruled out: `contents(of:at:)` plus an
in-process diff — git already computes exactly this.

### The submenu obeys the row

Files under the repository get the submenu; untracked files get Against Last
Commit disabled (there is no last commit of them) but History… absent too —
git has no history to show; folders, dependencies, compiler roots and
session rows get no submenu, the way their menus already prune what does not
apply. The truth-telling is `menuNeedsUpdate`'s job, where the row's other
items already decide.

## Risks / Trade-offs

- [A renamed file's "Against Last Commit" diffs against nothing at the new
  path] → the same behaviour every diff in the app has today for renames;
  History… still follows the rename, which is the stronger answer.
- [Compare with Working Copy on an old commit of a huge file] → the diff tab
  already carries its 5,000-line bound; nothing new to bound.
- [Two doors to the log page can drift] → both call the same `showLogPage` +
  scope path; the drive asserts the scope control's state.

## Open Questions

- Whether the editor tab's context menu should carry the same submenu is
  left until somebody reaches for it there; the actions will be one selector
  away.
