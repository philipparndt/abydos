## 1. One list, one layout

- [ ] 1.1 In `HistoryPane.rebuild`, work out what is hidden and build `visible` *before* laying the graph out, and lay it out over that list.
- [ ] 1.2 Drop a collapsed merge's hidden parents from the node handed to the layout, so no lane is reserved for a commit that is never reached.
- [ ] 1.3 Check `rebuildFadedLanes` still agrees with the new layout rather than assuming it does — both features draw lanes and neither knew about the other.

## 2. Proving it

- [ ] 2.1 A unit test beside `GitGraphTests`: no lane in the output belongs to a commit that was not in the input.
- [ ] 2.2 Driven: fold a merge and read the page report, showing no lane below it belongs to a hidden commit; unfold and show the graph is the one from before.

## 3. Finishing

- [ ] 3.1 `make test` and `make warnings`, both clean, both by their exit codes.

Nothing here makes a `.abydos/backlog/spec/*.md` file untrue: that backlog is
gone and its account is `openspec/specs`.
