## Why

The refs tree shows tags alphabetically, so finding the tag that was just cut
means knowing its name rather than looking at the top — and alphabetical order
lies about versions anyway (`v1.10` sorts before `v1.9`). The odd part, found
by reading the code: `GitBranches.list` already asks git for tags
`--sort=-creatordate`, newest first, with a comment saying why ("an old tag is
rarely what anyone is looking for") — and `PathTree.sort` then re-sorts the
rows by display name before they are drawn. The order the feature wants is
fetched on every refresh and discarded in the view.

There is no originating `.abydos/backlog` item: this comes from a direct
request, 2026-08-31 — tags newest first by default, the order changeable from
the Tags node's context menu, and the same options on the other section nodes.

## What Changes

- The TAGS section shows tags by creation date, newest first, by default.
- The context menu of the TAGS section header offers the sort orders — by
  creation date (newest first) and by name — with a tick on the one in force.
  The LOCAL and each remote section header offer the same choice; their
  default stays by name, which is what they show today.
- The choice is remembered between sessions, per section kind (local,
  remotes, tags) — the way the log page's tree arrangement is remembered.
- The titlebar branch pill follows the LOCAL section's order, keeping the
  existing requirement that two lists of the same branches in one window do
  not disagree.
- The filtered (flattened) list respects the same choice.
- Section headers gain their first context-menu items; today a right-click on
  `LOCAL`/`ORIGIN`/`TAGS` falls through to the tree's catch-all menu.

## Capabilities

### Modified Capabilities

- `git-refs-tree`: gains requirements for the default tag order, the sort
  choice on section headers, its persistence, and its reach (folding, the
  filtered list, the titlebar pill). Additions only — no existing requirement
  states the order of rows within a section, and the one sentence about
  order-agreement with the pill is kept by making the pill follow.

### New Capabilities

<!-- none -->

## Impact

- **AbydosKit**: `GitBranch` gains a creation date (`%(creatordate:unix)`
  appended to the `for-each-ref` format, with the same care the
  `%(ahead-behind:)` fallback takes); `PathTree.build` gains an ordering
  parameter beside `folding:`/`promoting:` so all three trees keep the one
  builder; `BranchGrouping.arrange` takes the same order for the pill.
  New tests beside `PathTreeTests` and `GitBranchesTests`.
- **AbydosApp**: `BranchesPane.appendSection` passes each section's order
  (both the tree path and the filtered path); `menuNeedsUpdate` gains a
  section-header case with checkable items; `menuTitlesForTesting` learns to
  print ticks; `Settings` gains keys per section kind.
- **Cost**: none per row — the comparator runs where the alphabetical one
  already runs; the extra format field rides on the existing `for-each-ref`.
- The `--count=100` cap on tags keeps selecting the hundred *newest* whatever
  the display order, which is today's selection behaviour.
