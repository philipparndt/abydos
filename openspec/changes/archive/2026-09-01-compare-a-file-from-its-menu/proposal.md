## Why

Both destinations already exist and neither is reachable from the file it is
about. The diff tab shows a file's working-copy changes — but only by finding
the file again in the changes tree; the log page scopes to one file's history,
`--follow` and all — but only from the "This File" segment after the log is
already open on something. A file row in the project tree, which is where
somebody is looking when they wonder "what did I change here" or "what did
this look like before", offers New, Rename and Move to Trash, and nothing
about time.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-09-01.

## What Changes

- A file's context menu in the project tree gains a Compare submenu with two
  entries: **Against Last Commit** — the file's working-copy diff against
  HEAD, opened as the diff tab that already exists — and **History…** — the
  log page opened scoped to that file, the same page the "This File" segment
  reaches.
- On a file-scoped log, a commit's menu gains **Compare with Working Copy**:
  the file as it is now against the file as that commit left it (`git diff
  <hash> -- <path>`), opened as a diff tab — which is the "compare to older
  versions" half of the request. Selecting a commit already shows what that
  commit changed; this answers the other question, "how far is *now* from
  then".
- Rows that are not files under the repository — folders, dependencies,
  session roots, untracked files with nothing to compare against — offer the
  submenu disabled or not at all, whichever the row's existing menu shape
  prescribes.

## Capabilities

### Modified Capabilities

- `project-view`: an added requirement — a file row's menu carries the two
  ways of comparing the file, both leading to surfaces that already have
  specs of their own.
- `git-pages`: an added requirement — a commit on a file-scoped log offers
  comparing that version with the working copy.

### New Capabilities

<!-- none: both destinations are specified; the change is the doorways. -->

## Impact

- **AbydosApp**: `ProjectNavigatorViewController`'s menu gains the submenu
  and two actions wired to `SidebarController.showDiff`-shaped plumbing and
  `showLogPage` + the pane's file scope; `HistoryPane`'s commit menu gains
  one item, shown only when the log is path-scoped.
- **AbydosKit**: little or nothing — `GitWorkingCopy.diffAgainstHead` and
  `GitHistory.log(path:)` exist; the commit-vs-working-copy diff is one
  argument's difference from diffs already run.
- **Driver**: the navigator menu report and the log page's `menu:` step
  already print menus; the new entries appear in both.
