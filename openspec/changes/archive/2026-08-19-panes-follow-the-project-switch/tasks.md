## 1. See it first

- [x] 1.1 A driver verb that switches project in a running window, since
      `switchProject` is reachable from the terminal and from the switcher but
      not from a flag. Two scratchpad projects, never a real checkout.
- [x] 1.2 Drive it and record what the pane shows before the fix, so the
      requirement is against a measured fault rather than a read one.
- [x] 1.3 The same for the search pane, measured the same way: with the call
      disabled, a search of `search-a` for `needle` still reported `3 in 3 files`
      after the window had switched to `search-b` — results from the tree that
      was left, each one a path that still opens. With the call in place the
      status is empty and the query is kept.


## 2. The backlog pane follows

- [x] 2.1 `backlog` and `openSpec` stop being `let`.
- [x] 2.2 `init`'s tail becomes one function — rebuild both, re-ask `exists`,
      re-pick `source`, `showContent()`, `reload()`, `watch()` — called by `init`
      and by `setProject`. One function, because two that must agree about what
      a project means will not.
- [x] 2.3 `setProject` stops both watchers and nils them, so `watch()` starts new
      ones. The guard is `if watcher == nil` and this is the half that fails
      silently.
- [x] 2.4 Same root does nothing, the way `ScratchesPane.setProject` bails.
- [x] 2.5 Called from `load(project:)` with `project.root`, beside
      `scratchesPane?.setProject`. **Not** from `setWorkingDirectory`, which is
      also called with a subproject scope and would empty the board on entering
      one.
- [x] 2.6 A pane that was never made is not made.

## 3. The search pane follows

*Droppable whole. Included because a stale result list opens files in a tree the
window has left, not because it was asked for.*

- [x] 3.1 `projectRoot` and its `ProjectSearch` are re-pointed the same way.
- [x] 3.2 Results are cleared; the query is not.
- [x] 3.3 Told from the same line in `load(project:)`, through the panel, since
      the pane may be docked anywhere and the panel is what holds it.

## 4. Tests as claims

- [x] 4.1 The four claims, each driven rather than unit-tested, since both panes
      live in the app target where the suite cannot reach them — which 4.3 says
      is the rule for exactly this case:
      *follows the project* — `board=[project=proj-a]` → `[project=proj-b]`;
      *only openspec is shown as such* — `backlog=false openspec=true`;
      *the old watcher is stopped* — an item written into proj-a moves nothing;
      *the same project does nothing* — board identical either side.
- [x] 4.2 The watcher claim needs a file touched in the project that was left and
      a wait for something that must **not** happen. Count-based, not
      wall-clock: assert the board's contents rather than that a second passed.
      `WaitUntil` polls off the cooperative pool for exactly this reason.
- [x] 4.3 Where the state is only reachable through the window — both panes live
      in the app target — the claim is checked by driving, and the report says
      what it saw.

## 5. Watched

- [x] 5.1 Two scratchpad projects with different backlogs, switched between,
      photographed both ways. Assert the project the window opened, every time:
      `--open` is a request, not a guarantee.
- [x] 5.2 A project with a backlog switched to one with only `openspec/`, and
      back, with the switch control appearing and disappearing.
- [x] 5.3 A project with neither, showing the offer to make one.

## 6. Finish

- [x] 6.1 `make test` and `make warnings`, both clean, exit codes trusted.
- [x] 6.2 Say whether the search pane half stayed in, and if it was dropped, say
      the fault is still there.
- [x] 6.3 Write down what was ruled out, including hanging this off
      `setWorkingDirectory` and what that would have done to a subproject.
