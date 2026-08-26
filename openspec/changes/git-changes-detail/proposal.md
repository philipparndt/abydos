## Why

A folder of untracked files is drawn as a file. `.abydos` and `PI-12` are
directories with work inside them, and both the sidebar's working-copy tree and
the commit page show them as two rows with a `?` beside them and nothing under
them — no folder icon, no disclosure triangle, no way to see what staging them
would add. The screenshots that came with the report show exactly two rows where
there are two directories.

This is not the listing being wrong. `GitWorkingCopy.status` asks git for
`-unormal` on purpose and the reason is measured: `-uall` took **7 seconds** on a
work tree with 69,829 untracked files, and the listing runs on every filesystem
event — dozens a minute during a build — where the same question with `-unormal`
is 0.11 s. A wholly untracked directory therefore arrives as one `dir/` record,
which is the right thing to receive and the wrong thing to draw as a file.

One other thing is missing from the same views. No row anywhere says how much
changed — every other tool that lists a diff puts `+12 −3` beside the name, and
this one makes you open a file to find out it was a one-line change.

## What Changes

- An untracked directory SHALL read as a directory in the working-copy tree and
  on the commit page — a folder icon, a disclosure triangle — and expanding it
  SHALL list what is inside it. Lazily, per directory:
  `GitWorkingCopy.contents(ofUntrackedDirectory:in:)` already asks `-uall`
  scoped to one path, which costs what that directory holds rather than what the
  work tree holds.
- Every changed file row SHALL carry the lines added and removed, and every
  folder row the sum of what is under it.
- The stale comment at `ChangesPane.swift:1388` — which says `-uall` reports the
  files inside an untracked directory individually, and concludes that a folder
  row is therefore always one the pane invented — is corrected. It has been
  untrue since the listing became `-unormal`, and it is the reason the pane
  believes something about its own rows that is no longer so.

## Capabilities

### New Capabilities

- `git-changes-detail`: what a row in a list of changes says about itself — its
  kind, whether it holds other rows, what is inside it when it does, and how
  much of it changed.

### Modified Capabilities

None. `openspec/specs/git-pages` describes the log and commit tenses of the page
— that it is a page in the editor area, that a one-line commit does not need it,
that a commit is an object with verbs — and says nothing about how the changed
files inside it are arranged or what a row shows. `openspec/specs/git-refs-tree`
describes the sidebar's sections and branch-name folders, and its "what holds
files expands to them" is about refs rather than about an untracked directory.
Neither has a requirement that changes.

## Impact

- `GitWorkingCopy` — the untracked-directory listing exists; what it needs is a
  caller. Plus `--numstat` for the working copy, which nothing asks for today.
- `GitChangeTree` — a row that holds files without being an invented folder, the
  contents under it, and the counts.
- `ChangesPane` — the folder row for an untracked directory, its lazy children,
  the counts, and the corrected comment.
- `BranchesPane` — the sidebar's own changes rows: the folder, and the lazy
  contents under it.

**The cost is the thing to watch, and it has bitten here before.** Two of these
ask git for something it is not asked for today — the contents of a
directory, and a diffstat — and both are on paths that run when a repository
changes. The measurement that produced `-unormal` is the precedent: what makes
the directory listing affordable is that it is scoped to one directory and asked
only when somebody opens that row. `--numstat` has no such scope, so what it
costs on a large commit and on a large working copy is a number this change owes
rather than an argument.

## Split

The log page's folder arrangement and the `*` key were proposed here and moved to
`git-log-page-tree` before they were built. This proposal assumed the page's
changes view was a tree that a toggle could re-point; it is a flat
`NSTableView`, sharing one data-source extension with the commit table, so
arranging it by folder means making it an outline first. That is a change to a
different pane with a different risk, and it deserved its own design rather than
a sentence in this one's.
