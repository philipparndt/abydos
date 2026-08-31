## 1. The date and the order (AbydosKit)

- [x] 1.1 `GitBranch` gains `created: Date?`; `%(creatordate:unix)` joins the `for-each-ref` format, with the retry-without fallback the `%(ahead-behind:)` field already has, and `parse` reads the new trailing field tolerantly
- [x] 1.2 A refs-tree sort order type (name / newest first) with raw values fit for a Settings key, living beside `GitBranches`
- [x] 1.3 `PathTree.build` gains an ordering parameter defaulting to today's name order: promoted rows first, folders before leaves and by name among themselves, leaves in the chosen order
- [x] 1.4 `BranchGrouping.arrange` takes the same order, so the pill can follow LOCAL
- [x] 1.5 Tests: `GitBranchesTests` parse a record with a creatordate and one without; a live fixture proves an annotated and a lightweight tag both carry dates; `PathTreeTests` prove date order among leaves, folders unmoved, promotion still first; a `BranchGroupingTests` claim for the date order

## 2. The pane (AbydosApp)

- [x] 2.1 Three Settings keys (local, remotes, tags), absent meaning name, name, created; in `resetToDefaults()`; `TestDefaults.make()` in every test touching them
- [x] 2.2 `appendSection` passes each section's order to `PathTree.build`, and the filtered path's inline sort becomes current-first then the section's order
- [x] 2.3 A `selectedHeader` accessor and a header case in `menuNeedsUpdate`: two checkable items in the `ResultPlacement` radio shape, one selector reading `representedObject`, writing the Settings key and calling `rebuildRows()`
- [x] 2.4 The titlebar pill reads LOCAL's key so the two lists agree
- [x] 2.5 `menuTitlesForTesting` prints the `✓ ` prefix for a ticked item, the way the titlebar's menu reports do

## 3. Proving it

- [x] 3.1 Drive `--branch-rows` against a scratch repository with tags whose dates invert their names: report shows newest first; fire the menu item for name order, report again, and the order flips and the tick moves
- [x] 3.2 The same drive on LOCAL: default is name order, switching to newest first reorders the branches and the pill's list agrees

## 4. Before finishing

- [x] 4.1 `make test` clean, `make warnings` clean (3915 tests green at load 37.6; one DrawioEditorLive flake in an earlier pass passed alone and in the clean full run)
- [x] 4.2 No `.abydos/backlog/spec/*.md` file is made untrue: nothing recorded the order of rows within a section; the delta in this change is its first account
