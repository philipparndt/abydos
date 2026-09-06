## 1. The sheet

- [ ] 1.1 `Sources/AbydosApp/Git/TagDeletion.swift` — one object per press,
  holding the tags, the root, the remote's name and the window, and **holding
  itself while its sheet is up**, which is `BranchDeletion`'s hard-won lesson:
  `ask` returns the moment the sheet appears, the caller lets the object go,
  and the completion handler then finds `self` nil and does nothing at all,
  with no error because nothing ran to fail. The comment says which bug that
  is for rather than repeating the reasoning.
- [ ] 1.2 What the sheet says: the tags by name with what each points at
  (`GitTags.describe`, which the move sheet already uses), and — only where
  the repository has a remote — *Also delete on `<remote>`*, unticked, named
  after the remote rather than "the remote".
- [ ] 1.3 What it runs: `GitTags.delete` first, then `GitTags.deleteOnRemote`
  where it was asked for, per tag, not stopping at the first remote failure.
  The report names each half — *deleted here, still on `origin`* — so nobody
  has to go to a terminal to find out which state they are in.

## 2. The rows

- [ ] 2.1 `BranchesPane` — the tag row's context menu gains *Delete Tag…*
  beside the move it already has, with the selection rule beside
  `deletableBranches`: the selected rows that are tags, offered only when
  every selected row is one.
- [ ] 2.2 The same verb from the keyboard, through the row-action gesture the
  tree already has, so the tags section is not the one place a row's own verb
  is pointer-only.
- [ ] 2.3 The tree reloads after either half, and a tag that is gone leaves no
  row behind — the same refresh the move already asks for.

## 3. Proving it

- [ ] 3.1 The driver: a step that opens the sheet on named tags, one that
  ticks the remote and one that agrees, in the shape the branch deletion's
  driven steps already have — so a run can say what the sheet said as well as
  what it did.
- [ ] 3.2 A driven run over a scratch repository with a **bare repository under
  the scratchpad as its `origin`** — nothing in the proof reaches anybody
  else's machine: a tag deleted locally with the remote left alone and
  `git ls-remote` still showing it; the same tag deleted on the remote and
  gone from both; two tags at once; a mixed selection offering nothing; and a
  repository with no remote offering no remote choice.
- [ ] 3.3 The remote-refuses case: `origin` pointed at a path that cannot be
  written, the local half standing and the report saying which half failed.

## 4. Finishing

- [ ] 4.1 `Scripts/file-size-allowed.txt` for what grew, reasons said aloud;
  `docs/release-notes-0.14.0.md` given the paragraph.
- [ ] 4.2 `make test` and `make warnings`, both clean by their exit codes.
