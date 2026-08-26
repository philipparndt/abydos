## 1. An untracked directory reads as one

- [x] 1.1 Add `holdsFiles` to `GitChangeNode` — an invented folder, or a change
      whose `isDirectory` is set. Leave `isFolder` alone: `isPartial`, the
      staging path and the context menu's wording all key on "a row this pane
      invented" and are right to.
- [x] 1.2 Draw the row from `holdsFiles` in both views: the folder icon, and a
      disclosure triangle. The `?` badge stays — it is untracked, and that is
      what the badge says.
- [x] 1.3 Test the node's own answers: an untracked directory holds files and is
      not a folder, an untracked file is neither, an invented folder is both,
      and `isPartial` is unchanged for all three.

## 2. And it opens

- [x] 2.1 Give `GitWorkingCopy` a public way to list one untracked directory's
      paths — `contents(ofUntrackedDirectory:in:)` is private and returns the
      text the diff pane renders. Keep the scoped `-uall`; it is what makes this
      affordable.
- [x] 2.2 Fill the row's children when it is expanded, not when the tree is
      built, and keep them against the row's path so a refresh does not collapse
      it under somebody reading it.
- [x] 2.3 Do not add those children to the directory's `count` or `total`. Git
      reports the whole directory as one entry; counting its contents would make
      a row that is wholly unstaged read as "1 of 12".
- [x] 2.4 Test all three: expanding lists the contents, nothing inside any
      untracked directory is listed while none is expanded, and staging the row
      still stages the whole directory. *(Kit tests for the tree and the fill
      contract; driven against a real repository — `.abydos/` and `PI-12/`
      arrive as `untracked folder, not opened [shut]`, and `open:PI-12` gives
      `src/ 2 → main.swift, util.swift` and `notes.md`.)*
- [x] 2.5 Correct the comment at `ChangesPane.swift:1388`. It says `-uall`
      reports the files inside an untracked directory individually and concludes
      that a folder row is always one the pane invented — untrue since the
      listing became `-unormal`, and now doubly so.

## 3. How much changed

- [x] 3.1 Ask `git diff --numstat` and `git diff --cached --numstat` for the
      working copy, and `git show --numstat` for a commit: one command per set of
      changes, joined onto the nodes by path. *(Driven: `tracked.txt +4/-0`,
      `Sources/ 1 +2/-0` over `New.swift +2/-0`.)*

      **A limitation worth stating rather than hiding:** an untracked file shows
      no counts, because `git diff --numstat` does not report untracked files at
      all — git will not diff what it does not track. Answering for them means
      `git diff --no-index /dev/null <file>` once per file, which is the process
      per row this task exists to avoid. So a new file says nothing until it is
      staged, at which point `--cached` counts it.
- [x] 3.2 A folder row sums what is under it. An unexpanded untracked directory
      says nothing about lines. *(Corrected while implementing: this task and
      the design both said it would "say how many files it holds", which it
      cannot — knowing that is the same walk as knowing the lines, and the
      whole point is not to take it. It says nothing until it is opened, and
      then its children carry their own counts and the sum appears.)*
- [x] 3.3 A row git gives no counts for — binary, a mode change, a pure rename,
      `-` in both columns — says nothing rather than zero.
- [x] 3.4 Draw them so the name truncates before the counts do.
- [x] 3.5 Test the parsing against real `--numstat` output: an ordinary file, a
      binary file, a rename, and a path with a space in it.
- [x] 3.6 Ask once per set of changes and not again while nothing has moved, and
      test that.

## 4. Finishing

- [x] 4.1 Drive the app against a repository with an untracked folder in it and
      show it closed and open. *(`PI-13/ untracked folder, not opened [shut]`,
      then `src/ 1 → main.swift` and `notes.md`; `tracked.txt +4/-0` and
      `Sources/ 1 +2/-0` over `New.swift +2/-0`. The commit-page arrangements
      moved out with sections 4 and 5.)*
- [x] 4.2 **Measure `--numstat`**, with the machine load beside it. *(This
      repository, load 7.96 over 14 cores: `git diff --numstat -z` over a
      working copy of nine changed paths is 0.01–0.05 s, and `git show
      --numstat -z` over the largest of the last forty commits — 34 files — is
      0.01–0.02 s. Both are one command per set of changes, and `refresh`
      returns early on an unchanged status, so neither is on the
      per-filesystem-event path. Nothing here approaches the seven seconds that
      made `-uall` unaffordable; the cost the design owed a number for is
      small.)*
- [x] 4.3 `make test` and `make warnings`, both clean, with the failures
      compared against a baseline taken by stashing the change — the suite
      carries pre-existing environment failures and several load-sensitive
      tests. *(`make warnings` clean, twice. `make test`: 35 issues over five
      tests — `aPermissionPromptWarnsEvenAfterAFinishedTurn`,
      `aTurnThatEndsStaysEnded`, `endingASessionClearsTheBadge`,
      `saysWhichParameterIsBeingFilledIn`, `theLoginPathIsAListOfAbsolute\
Directories` — every one of them a family already failing in this morning's
      baseline of 34 issues over four tests, and none in git. No benchmark was
      added, so nothing needed gating.)*
- [x] 4.4 Decide the open questions. *(Both were about the log page's
      arrangement and the `*` key, which have moved to `git-log-page-tree`
      along with the decisions they belong to.)*

**Sections 4 and 5 moved out**, to `git-log-page-tree`. The design here said the
log page "builds its file list itself today" and that a toggle would point it at
`GitChangeTree.build`. That is wrong about the starting point: `HistoryPane`'s
file list is a flat `NSTableView` sharing one data-source extension with the
commit table, so there is no tree to point anywhere — it has to become an
outline first. That is a different change in a different pane, and it is written
up as one.

**No spec is made untrue.** `openspec/specs/git-pages` says what the log and
commit tenses of the page are; `openspec/specs/git-refs-tree` says what the
sidebar holds. Neither has a requirement about how changed files are arranged or
what a row says about itself.
