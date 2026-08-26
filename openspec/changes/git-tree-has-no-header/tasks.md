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

- [ ] 4.1 `⌘F` while the pane holds the keyboard opens a filter strip over the
      list, with the keyboard in it
- [ ] 4.2 `esc` closes it; emptying it closes it; the tree is unfiltered after
- [ ] 4.3 Filtering behaves exactly as it does today once open — the flattening
      is untouched
- [ ] 4.4 Confirm with the menu-key report that `⌘F` reaching the pane does not
      take it from the editor when the editor has the keyboard
- [ ] 4.5 Delete `filterField` and `newButton` and their constraints

## 5. A folder with verbs of its own keeps its row

- [ ] 5.1 `PathTree.build` takes the folder names that are never folded into
      their only child; the refs tree names `backup` among them
- [ ] 5.2 `hotfix/0472` is unchanged — one row, no folder
- [ ] 5.3 Tests over `PathTree` for both: one backup ref keeps its folder, one
      hotfix branch does not gain one
- [ ] 5.4 Driven: a repository with a single backup ref shows the folder, and
      the folder's own verbs are on it

## 6. A merged branch is dimmed

- [ ] 6.1 `GitBranches` answers which local branches are merged into the default
      branch, read alongside what the pane already reads
- [ ] 6.2 `BranchRowView` draws a merged branch dimmed; the current branch never
      dims, whatever the answer says
- [ ] 6.3 A branch the reading has not covered draws as it does today
- [ ] 6.4 Driven: a merged branch and an unmerged one, reported side by side

## 7. Proving it

- [ ] 7.1 The tree begins at the top of the pane, under the repository row, and
      nothing else takes height above it — measured in a driven run, not by eye
- [ ] 7.2 Every action reachable by pointer is reachable by `⌘⏎` or a context
      menu, and the driven report says which
- [ ] 7.3 `make test` and `make warnings` green
- [ ] 7.4 A screenshot at 300 and at 250 points wide, compared against the
      header the change removes
