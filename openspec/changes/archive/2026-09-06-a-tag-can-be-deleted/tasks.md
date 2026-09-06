## 1. The sheet

- [x] 1.1 `Sources/AbydosApp/Git/TagDeletion.swift` — one object per press,
  holding the tags, the root, the remote's name and the window, and **holding
  itself while its sheet is up**, which is `BranchDeletion`'s hard-won lesson:
  `ask` returns the moment the sheet appears, the caller lets the object go,
  and the completion handler then finds `self` nil and does nothing at all,
  with no error because nothing ran to fail. The comment says which bug that
  is for rather than repeating the reasoning.
- [x] 1.2 What the sheet says: the tags by name with what each points at
  (`GitTags.describe`, which the move sheet already uses), and — only where
  the repository has a remote — *Also delete on `<remote>`*, unticked, named
  after the remote rather than "the remote".
- [x] 1.3 What it runs: `GitTags.delete` first, then `GitTags.deleteOnRemote`
  where it was asked for, per tag, not stopping at the first remote failure.
  The report names each half — *deleted here, still on `origin`* — so nobody
  has to go to a terminal to find out which state they are in.

## 2. The rows

- [x] 2.1 `BranchesPane` — the tag row's context menu gains *Delete Tag…*
  beside the move it already has, with the selection rule beside
  `deletableBranches`: the selected rows that are tags, offered only when
  every selected row is one.
- [x] 2.2 The same verb from the keyboard, on ⌘⌫ — this app's delete gesture,
  which the project tree has trashed files with since it had a tree. Not the
  ⌘⏎ row action, which fires the trailing button a tag row does not have.
  Branches are deliberately left alone: their delete asks about worktrees and
  about commits nothing else has, and a bare key is too small a gesture for
  that question; the key is a no-op unless every selected row is a tag.
- [x] 2.3 The tree reloads after either half, and a tag that is gone leaves no
  row behind — the same refresh the move already asks for.

## 3. Proving it

- [x] 3.1 The driver: `--branch-rows delete-tag` for the local half and
  `delete-tag:remote` for both, which say what the sheet would have said —
  the tags, where each points, the remote's name and the answer given — and
  then do what agreeing to it does, through the same `delete` the button
  calls. **The sheet itself stays undriven**: `NSAlert` wants a person, and a
  harness reaching in to press its button would be testing `NSAlert`.
  `branchMenuTitlesForTesting` gained the `(off)` mark the per-row report
  already had, because a shown-and-disabled item is a different answer from an
  absent one and the report could not tell them apart.
- [x] 3.2 Driven on 2026-09-06 over a scratch repository whose `origin` is a
  bare repository beside it under the scratchpad — nothing in the proof
  reaches anybody else's machine:
  - *The menu:* a tag row offers *Recreate…* and *Delete Tag…*.
  - *Local only:* `v1.0` deleted with the remote left alone — gone from the
    tree and from `git tag`, and `git ls-remote --tags origin` still showing
    `refs/tags/v1.0`.
  - *Both halves:* `v1.1` with the remote asked for — gone from `git tag` and
    from `git ls-remote`.
  - *Two at once:* `v2.0` and `v2.1` selected together, both gone from both.
  - *A mixed selection:* `main` and `v1` together report the menu item as
    *Delete Tag… (off)*, and the delete answers "nothing selected" with the
    tag still there.
  - *No remote:* a repository with no remotes reports `remote=none`, and the
    delete takes the tag with no push attempted.
- [x] 3.3 The remote-refuses case: `origin` pointed at a path with no
  repository in it, and the toast read *Deleted here, still on origin:
  refused2: fatal: '…does-not-exist.git' does not appear to be a git
  repository* — the local half standing, the failure named, and which state
  the repository is in said rather than left to be worked out.

## 4. Finishing

- [x] 4.1 `Scripts/file-size-allowed.txt` raised for what grew:
  `BranchesPane.swift` 4599 → 4686 (the menu item, the selection rule, the two
  doors and the ⌘⌫ wiring) and `SidebarController.swift` 1719 → 1724 (the
  driver step). `docs/release-notes-0.14.0.md` has the section.
- [x] 4.2 Green by their exit codes: `make test` 4104 tests in 522 suites,
  exit 0 with the suite's two standing known issues, load 70.7 over 10 cores;
  `make warnings` exit 0.
