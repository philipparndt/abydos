## Context

Tags already arrive from git newest-first: `GitBranches.list` runs a second `for-each-ref` with `--sort=-creatordate --count=100`. The order dies in `PathTree.sort`, which ranks promoted rows first, then folders, then `localizedStandardCompare` on names — the one comparator shared by the project tree, the changes tree and the refs tree, on purpose (the spec's words: a third builder that sorted differently would be a difference in one window nobody could explain). `BranchesPane.appendSection` is the single funnel through which LOCAL, each remote and TAGS build their rows, with a separate inline sort on the filtered path. Section headers (`Row.header`) have no context-menu case of their own today, and nothing in `BranchesPane` is persisted. The titlebar pill sorts local branches with its own `BranchGrouping.arrange`, and the spec requires the two lists never disagree.

## Goals / Non-Goals

**Goals:**

- Tags newest-first by default; by name on request. Local and remote sections offer the same two orders, defaulting to by name — what they show today.
- One choice per section kind (local, remotes, tags), remembered between sessions, applying to the folded tree and the filtered flat list alike.
- The pill follows LOCAL's choice, so the order-agreement requirement stands untouched.
- The comparator lives in the shared builder as a parameter, not in a second builder.

**Non-Goals:**

- No third order. Version-aware sorting (`--sort=-version:refname`, the `v1.10 > v1.9` order `GitTags.likelySource` uses) is a natural later option; newest-first already puts the latest release on top, which is the request.
- No per-repository memory: the choice is a reading habit, not a property of a checkout — the same call `commitFilesByFolder` made. Per-remote-name memory likewise not: the sections collapse to three kinds and the menu offers exactly those.
- No date column on tag rows; the order carries the information. A tooltip can say the date some other day.
- No re-sorting of Worktrees, Stashes or Submodules — nobody asked, and stashes are already a chronology.

## Decisions

### The date rides on the existing `for-each-ref`

`GitBranch` gains `created: Date?`, parsed from `%(creatordate:unix)` appended to the format. `creatordate` is the right field for both tag flavours — the tagger date of an annotated tag, the committer date of what a lightweight one points at — and it costs nothing extra: the field joins a call already made on every refresh. It is populated for branches too, since the same format serves `refs/heads` and `refs/remotes`, which is exactly what LOCAL/ORIGIN need. Ruled out: a separate `git tag --list` or per-tag `cat-file` — a second child process per refresh to learn what the first one already knows. Care copied from `%(ahead-behind:)`: an old git that rejects the field fails the whole command, so the same retry-without shape guards it (`creatordate` is ancient, but the fallback is four lines and the failure mode is a blank sidebar).

### The comparator is a parameter of the one builder

`PathTree.build` gains an ordering parameter beside `folding:`, `keeping:` and `promoting:`, defaulting to today's name order so the project tree and changes tree are untouched call sites. Within a level: promoted rows first (unchanged), then folders, then leaves in the chosen order. Ruled out: sorting the entries before `build` and telling the tree to keep insertion order — the tree sorts per level after grouping, so pre-sorting cannot survive folding, and a keep-order mode is a second code path through the exact function the spec says must stay singular.

### Folders keep their place and their name order under a date sort

A folder has no creation date of its own. Under the date order, folders still come first within a level and sort among themselves by name; only leaves take the date. Ruled out: ranking a folder by its newest descendant — it makes a folder's position change because of something invisible inside it, and the sections where date order matters most (TAGS) rarely fold at all. If somebody with dated release folders asks, the derived key can be added without changing the parameter's shape.

### The menu is on the section header, checkable, three kinds

`BranchesPane` gains a `selectedHeader` accessor beside `selectedFolder`, and `menuNeedsUpdate` a branch before the catch-all: two checkable items, "Newest First" and "By Name", tick on the one in force, following the `ResultPlacement` radio pattern (`representedObject` carrying the raw value, one selector reading it back). The header keeps its existing row action (the plus button); the menu is where options live. `menuTitlesForTesting` learns the `✓ ` prefix the titlebar's menu reports already use, so the tick is visible to a driven run.

### Persistence: three global keys, defaulting per kind

`Settings` gains one string key per section kind — local, remotes, tags — holding the order's raw value, absent meaning the default (name, name, created). Global rather than per repository, matching `commitFilesByFolder` and its spec's argument ("choosing again for every commit is choosing nothing"). Added to `resetToDefaults()` like every key. `TestDefaults.make()` in every test that touches them, as the guard test enforces.

### The pill follows LOCAL

`BranchGrouping.arrange` takes the same order value the LOCAL section uses, so the requirement "two lists of the same branches in one window SHALL NOT disagree about their order" is honoured rather than amended. Ruled out: qualifying the requirement — it exists because the disagreement was seen and disliked once already.

### The filtered list obeys the same choice

The filtered path's inline sort (current first, then name) becomes current first, then the section's order. A filter narrows what is shown, not how it is ordered.

## Risks / Trade-offs

- [A repository with more than 100 tags shows the 100 newest, and under "By Name" that is an alphabetical view of a newest-100 selection] → unchanged from today, where the cap already exists and the display was alphabetical; the cap keeps selecting by newness whatever the display order, and the design says so out loud rather than hiding it.
- [`GitBranch: Equatable` drives `BranchesPane.refresh`'s short-circuit; a new field joins the comparison] → dates are stable between refreshes, so the short-circuit still holds; a commit moving a branch tip changes the date exactly when the row should redraw anyway.
- [Old git rejecting `%(creatordate:unix)` would blank the sidebar] → the retry-without fallback, tested the way the `%(ahead-behind:)` one is.
- [The menu grows on rows that never had one, so the catch-all's `New Worktree…` disappears from headers] → deliberate: a header names a set, and the set's verbs (add, sort) belong there; the worktree verb remains on every row the catch-all still serves.

## Open Questions

- Whether "Oldest First" earns a place as a third option is left until somebody wants it; the menu's radio shape takes a third item without redesign.
