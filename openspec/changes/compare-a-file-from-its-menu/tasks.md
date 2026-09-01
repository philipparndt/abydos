## 1. The doorways (AbydosApp)

- [ ] 1.1 The Compare submenu in `ProjectNavigatorViewController`'s file menu: Against Last Commit and History…, with `menuNeedsUpdate` pruning per the row's truth (untracked: first item disabled, no History…; non-file rows: no submenu)
- [ ] 1.2 Against Last Commit runs `GitWorkingCopy.diffAgainstHead` for the row's path and opens the diff tab through the sidebar's existing plumbing
- [ ] 1.3 History… opens the log page scoped to the file (`showLogPage` + the pane's file scope), the scope control landing on "This File"

## 2. Comparing with an older version

- [ ] 2.1 `HistoryPane`'s commit menu gains Compare with Working Copy, present only while the log is path-scoped; it runs `git diff <hash> -- <path>` and opens the result as a diff tab
- [ ] 2.2 A kit seam only if one is missing: the hash-vs-working-copy diff for one path, beside `diffAgainstHead`, with a live test proving it shows the distance from an older commit

## 3. Proving it

- [ ] 3.1 The navigator's driven menu report shows the submenu on a tracked file, the disabled shape on an untracked one, and its absence on a folder
- [ ] 3.2 A driven run on a scratch repository: Against Last Commit opens a diff carrying both a staged and an unstaged edit; History… lands on the file-scoped log; Compare with Working Copy on an older commit opens a diff naming the distance

## 4. Before finishing

- [ ] 4.1 `make test` clean, `make warnings` clean, machine load said if a bound flakes
- [ ] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: the file menu's compare verbs were unrecorded; both deltas add beside requirements they leave standing
