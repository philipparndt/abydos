## 1. A row can carry a verb

- [ ] 1.1 A trailing action rect on the branch row view — computed at draw time,
      drawn when the row has one, hit-tested in `mouseDown` before the row's own
      gesture, as the tab bar's trailing controls already are
- [ ] 1.2 Shown always, or on hover-and-selection, per row; selection counts as
      hover so a row arrowed to shows what it offers
- [ ] 1.3 `⌘⏎` fires the selected row's action; `⏎` still checks a branch out
- [ ] 1.4 `LOCAL` is its first user: a `+` that opens the same dialog the
      `New Branch…` button opens. The button stays for now
- [ ] 1.5 Driven: report which rows offer an action, and fire one from the
      keyboard

## 2. The working copy's verb

- [ ] 2.1 The working copy row offers `Review 1 change…` — the count in words,
      pluralised — whenever it has anything to commit, and nothing when clean
- [ ] 2.2 The context menu entry and `⇧⌘K` say the same words
- [ ] 2.3 Driven: a dirty working copy offers it, pressing it opens the commit
      view, and nothing is committed by pressing it
- [ ] 2.4 Driven: a clean working copy offers nothing

## 3. The repository row

- [ ] 3.1 A `repository` case on the row model, drawn by the same row view:
      project, branch, and the distance from upstream in words
- [ ] 3.2 A one-row outline above the scroll view, sharing the model, the row
      view and the metrics, with no selection of its own
- [ ] 3.3 It carries the traffic control: fetch when level, pull when behind,
      push when ahead — `refreshTraffic` moves onto it, `GitPush.state` unchanged
- [ ] 3.4 No remote, and an upstream that is gone, each say what they are
- [ ] 3.5 Delete `trafficButton` and its constraints
- [ ] 3.6 Driven: scroll the tree to the bottom and confirm the row is still
      there; check the wording at 250 points wide

## 4. The filter, on `⌘F`

- [ ] 4.1 `⌘F` while the pane holds the keyboard opens a filter strip over the
      list, with the keyboard in it
- [ ] 4.2 `esc` closes it; emptying it closes it; the tree is unfiltered after
- [ ] 4.3 Filtering behaves exactly as it does today once open — the flattening
      is untouched
- [ ] 4.4 Confirm with the menu-key report that `⌘F` reaching the pane does not
      take it from the editor when the editor has the keyboard
- [ ] 4.5 Delete `filterField` and `newButton` and their constraints

## 5. Proving it

- [ ] 5.1 The tree begins at the top of the pane, under the repository row, and
      nothing else takes height above it — measured in a driven run, not by eye
- [ ] 5.2 Every action reachable by pointer is reachable by `⌘⏎` or a context
      menu, and the driven report says which
- [ ] 5.3 `make test` and `make warnings` green
- [ ] 5.4 A screenshot at 300 and at 250 points wide, compared against the
      header the change removes
