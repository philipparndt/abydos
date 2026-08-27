## 1. A row can carry a verb

- [x] 1.1 A trailing action rect on the branch row view — computed at draw time,
      drawn when the row has one, hit-tested in `mouseDown` before the row's own
      gesture, as the tab bar's trailing controls already are
- [x] 1.2 Shown always, or on hover-and-selection, per row; selection counts as
      hover so a row arrowed to shows what it offers
- [x] 1.3 `⌘⏎` fires the selected row's action; `⏎` still checks a branch out
- [x] 1.4 `LOCAL` is its first user: a `+` that opens the same dialog the
      `New Branch…` button opens. The button stays for now
- [x] 1.5 Driven: report which rows offer an action. Firing one is driven in
      2.3 instead — `Local`'s verb opens a sheet, and a driven run that opens a
      sheet is a driven run that stops

## 2. The working copy's verb

- [x] 2.1 The working copy row offers `Review 1 change…` — the count in words,
      pluralised — whenever it has anything to commit, and nothing when clean
- [x] 2.2 The context menu entry and `⇧⌘K` say the same words
- [x] 2.3 Driven: a dirty working copy offers it, pressing it opens the commit
      view, and nothing is committed by pressing it
- [x] 2.4 Driven: a clean working copy offers nothing

## 3. The repository row

- [x] 3.1 `RepositoryRowView`, an `ActionableRowView` drawn through the same
      metrics: project, branch, and the distance from upstream in words. **Not a
      `Row` case** — see the design; the row model belongs to the outline and
      this row is not in one
- [x] 3.2 It sits above the scroll view, at a fixed height, with no selection of
      its own — keyboard focus instead, and `↓` off it into the tree
- [x] 3.3 It carries the traffic control: fetch when level, pull when behind,
      push when ahead — `refreshTraffic` hands it the state and nothing else
- [x] 3.4 No remote, nothing committed yet, never published, and an upstream
      that is gone each say what they are. **The gone case needed
      `GitPush.State` to gain a flag** — it parsed as level, which is a sentence
      about a ref that is not there
- [x] 3.5 Delete `trafficButton` and its constraints
- [x] 3.6 Driven: the tree scrolled to the bottom leaves the row where it was
      (`scrolled 0` → `scrolled 505`, row at `569–593` both times), and the
      wording holds at 250 points — **the project name drops before the
      sentence does**, the titlebar naming the project already

## 4. The filter, on `⌘F`

- [x] 4.1 `⌘F` while the pane holds the keyboard opens `PaneFilterStrip` over
      the list, with the keyboard in it
- [x] 4.2 A driven `⎋` closes it; emptying it closes it; the tree is unfiltered
      after — `44 rows → “b1” 13 rows → shut, 44 rows`
- [x] 4.3 Filtering behaves exactly as it does today once open — the flattening
      is untouched, and the screenshot shows `feature/b1` full-named with no
      `feature/` folder
- [x] 4.4 Driven from both sides: keyboard in the tree, Find is taken by
      `BranchesPane` and the strip opens; keyboard in the editor, Find is taken
      by `MainWindowController` and the editor's find bar opens while the pane
      stays shut. **Not the menu-key report** — that one is about which press
      reaches a shortcut, and the ⌘F binding is untouched here; what changed is
      who the responder chain hands the action to
- [x] 4.5 Delete `filterField` and `newButton` and their constraints

## 5. A folder with verbs of its own keeps its row

- [x] 5.1 `PathTree.build` takes `keeping:`, the folder names never folded into
      their only child; the refs tree names `backup` among them
- [x] 5.2 `hotfix/0472` is unchanged — one row, no folder
- [x] 5.3 Tests over `PathTree` for both, and for a kept folder nested under
      something else
- [x] 5.4 Driven: a repository with a single backup ref shows the folder, and
      the folder's own verbs are on it —
      `Collapse All · — · Delete Backups Older Than… · Copy Prefix`
- [x] 5.5 **The verb the folder was being kept for did not exist.**
      `git-refs-tree` has said the backup folder carries deleting the entries
      older than a given age since it was written, `GitBackup.sweep` has done
      it since it was written, and the menu offered the three verbs every
      folder has and no more. Wired, with the counts shown before the choice

## 6. A merged branch is dimmed

- [x] 6.1 `GitBranches.merged(into:in:)` — one `git branch --merged` beside the
      reads the pane already does, answering a set of names. The branch itself
      is taken out of git's answer: it is trivially merged into itself
- [x] 6.2 `BranchRowView` fades a merged branch — an alpha rather than a fixed
      dim colour, which would be a fourth meaning for a row's colour beside
      current, tag and plain. The current branch never dims
- [x] 6.3 A branch the reading has not covered is simply not in the set, so a
      slow or failed answer costs appearance rather than correctness
- [x] 6.4 Driven, side by side: `main *`, `done-work (merged)`, `still-going`,
      and tests over `merged` for both the answer and the empty case

## 8. The branch everything merges into is pinned

- [x] 8.1 `PathTree.build`'s `promoting:` becomes a rank rather than a flag —
      a flag can say *both of these go first* and not *this one of them goes
      first*, and there are two winners with an order between them
- [x] 8.2 The pane reads the default branch alongside its other reads and pins
      current, then default — the order `BranchGrouping.arrange` already pins
      for the branch pill, so the two lists of the same branches in one window
      cannot disagree
- [x] 8.3 Tests over `PathTree` for the ranked order
- [x] 8.4 Driven: on `zeta`, the list reads `zeta *`, `main`, then the folders
      and then the rest by name

## 9. The repository row says only what the titlebar does not

- [x] 9.1 The row drops the project name and the branch. Both are in the
      titlebar a few points above it, and on a repository with nothing to
      report the row was those two words and nothing else
- [x] 9.2 What is left is the distance and the verb — `level` and `no remote`
      still said out loud, so a pinned row always means something
- [x] 9.3 The width fallback and the short `↓2 ↑1` spelling go with the name
      they were making room for. Nothing is left that could need to give way
- [x] 9.4 Driven, and the four states re-checked

## 10. A branch says whether it has ever been published

- [x] 10.1 `GitBranch` gains `upstreamIsGone` and `isUnpublished`, parsed the
      same way `GitPush.State` learnt it; the row reads `not published` where
      the arrows go, and says it quietly — a count is news, this is a standing
      fact
- [x] 10.2 The current branch is no different — it is the row that says it now
      that the repository row does not
- [x] 10.3 Driven, side by side: `main *`, `feature [upstream gone]`,
      `never-pushed [not published]`

## 11. The change counts line up

- [x] 11.1 `ChangeColumns` measures the widest `+n`, `−m` and tally on each side
      once per reload; both row views draw right-aligned on those three x's
- [x] 11.2 The name takes what is left, as it already did — a file row now also
      reserves the tally column it never draws in, which is what alignment costs
- [x] 11.3 Driven at 420 and 250 points, reporting the columns themselves and
      not only the values: a report of the values would have read the same
      before they lined up as after

## 12. The trailing end of a branch row is a column

- [x] 12.1 `RowMetrics.trailingGlyph` and `drawTrailing` — one right edge every
      branch row draws its last mark on, instead of trailing whatever the name
      left
- [x] 12.2 The fitted glyph box is right-aligned on the image's own ink, not
      centred in a square slot: a tick is taller than it is wide and landed
      short of the edge the text beside it sat flush on
- [x] 12.3 `not published` and `upstream gone` become `icloud.and.arrow.up` and
      `xmark.icloud`; the words move to the tooltip
- [x] 12.4 A merged branch draws a tick in the same column, undimmed, and it
      outranks both cloud symbols
- [x] 12.5 The report names the symbol rather than the sentence it replaced — a
      report saying `not published` while the row draws a cloud cannot catch
      the cloud being wrong
- [x] 12.6 Driven with all four in one repository: `main * [↑2 ↓1]`,
      `local-only [icloud.and.arrow.up]`, `orphaned [xmark.icloud]`,
      `shipped [checkmark]`

## 13. An unpublished branch is measured against main

- [x] 13.1 `GitBranches.list(in:comparedTo:)` asks `%(ahead-behind:)` in the
      listing already being made, and falls back to the format without it —
      the atom arrived in git 2.41 and an older git refuses the whole command
      over it, which would take every row away to get a nicer number
- [x] 13.2 The pane reads the default branch first, the listing being measured
      against it
- [x] 13.3 The count draws beside the symbol rather than instead of it: both
      are true and neither implies the other
- [x] 13.4 **Only the ahead half.** `↓1557` against the default branch borrowed
      this pane's remote vocabulary to say something else — not *commits to
      pull* but *main has moved on* — and was read as the first, which is the
      only way it can be read on a row where every other arrow means that. `↑`
      survives because it does not change meaning between the two readings.
      The figure that could not be drawn honestly is in the tooltip, in words
- [x] 13.5 The report says which the count is against — the same arrow means a
      different thing on an unpublished row
- [x] 13.6 Driven: `local-only [↑2 of the default icloud.and.arrow.up]`

## 14. A branch row offers to open a pull request

- [x] 14.1 `GitForge.Repository.url(forPullRequestFrom:into:)` — the compare
      page with the branches filled in, spelled GitHub's way, for the hosts
      this type already claims
- [x] 14.2 `Publish and Open Pull Request…` on a branch with no upstream,
      `Open Pull Request…` on one that has been published
- [x] 14.3 The publish happens first and the page is not opened if it fails
- [x] 14.4 Nothing offered for the default branch, or without a forge
- [x] 14.5 Driven over three branches with a GitHub remote

## 7. Proving it

- [x] 7.1 The tree begins at the top of the pane, under the repository row, and
      nothing else takes height above it — `row at 683–707 of 707`, measured in
      a driven run
- [x] 7.2 Every action reachable by pointer is reachable by `⌘⏎` or a context
      menu, and the driven report says which:
      `working: Review 4 changes… · section:Local: plus (on hover) ·
      Local:local:main: -`. The pinned row's own `⌘⏎` is counted rather than
      watched — `Pull` opens a dialog, and a driven run that opens one stops,
      so the count answers the question in doubt (did the key reach the row)
      instead of the one that is not (what the row then did): `fired 0 → 1`
- [x] 7.3 `make test` and `make warnings` green
- [x] 7.4 Screenshots at 300 and at 250 points wide
