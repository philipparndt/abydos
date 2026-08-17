# 525. The dependencies section cannot read a pnpm or a yarn project

Item 514 taught the project view's **Dependencies** section to read npm: a
`package-lock.json` names every package, and the lock file's own keys are the
paths under `node_modules`, so the sources come free.

It stopped there on purpose. `package.json` is the marker for all three tools,
so a pnpm project and a yarn project both reach npm's reader, and neither has a
`package-lock.json`. 514 made them say which tool resolved them:

    resolved by pnpm — pnpm-lock.yaml not read yet (0525)
    resolved by yarn — yarn.lock not read yet (0525)

which is this item. Without that sentence the row would have read `no
package-lock.json — run npm install`, which is a suggestion to install a
second, conflicting tree over somebody's working project — the same shape of
lie 513 found on a Cargo workspace member.

## What it takes

- **`pnpm-lock.yaml` is YAML and there is no YAML reader in this repository.**
  That is 513's "there is no TOML reader" again, and the answer there was
  thirty lines rather than a dependency, because `Cargo.lock` is generated and
  flat. `pnpm-lock.yaml` is nested — `packages:`, `snapshots:`, `importers:`,
  keys like `/lodash@4.17.21` with quoting rules — so the same argument has to
  be made again on its own merits before either a dependency or a hand-written
  parser is chosen. `project.md` asks for the argument.
- **Three yarn formats, not one.** yarn v1's `yarn.lock` is bespoke (a
  colon-terminated header naming one or more ranges, then indented fields);
  berry's is YAML with `__metadata`. The `version` field in `.yarnrc.yml` or
  the lock's own header says which.
- **The sources may not be a directory at all.** pnpm's `node_modules` is a
  tree of symlinks into `.pnpm/<name>@<version>/node_modules/<name>`, which a
  package row can still be rooted at — 508's "a package row is a directory"
  holds if the symlink is followed. Yarn berry with Plug'n'Play has *no*
  `node_modules`: the packages are zip files under `.yarn/cache`, and there is
  nothing to browse without reading a zip. A package with no sources is a state
  the row already knows how to show (`localPath` is optional), so PnP may
  simply be name, version and origin.
- **The kind is still called `npm`.** `DependencyKind` is keyed off the marker
  file and `package.json` is the marker for all three, so a pnpm project's
  section heading says `npm` today. Whether that becomes three kinds, or one
  kind whose title is read off the lock file, is part of this item.

## Where the work goes

`Sources/AbydosKit/Project/ExternalDependencies.swift`, beside `readNpm` —
which already names all four lock files and picks between them, so the branch
this item fills in is already there and already tested.

## Ruled out

Nothing yet. 514's own ruled-out list has the argument for why this is a
separate item rather than the rest of that one.

## Estimate

2026-08-17 10:05 — about three hours left

## Steps

- [x] Decide whether YAML is a dependency, a hand-written reader, or neither,
      and write the argument down the way 513 did for TOML
- [x] Read `pnpm-lock.yaml` into packages: name, version, origin — every
      layout still on this machine, which is 5.4's `/name/version` and 9.0's
      `name@version`
- [x] `snapshots:` is not read, or every package is drawn twice
- [x] Read `yarn.lock`, both syntaxes — v1's own and berry's YAML
- [x] Decide what a yarn entry that is not a package from a registry does:
      `workspace:`, `link:`, `portal:`, `patch:`
- [x] The sources: pnpm's `.pnpm/<name>@<version>/node_modules/<name>`, and
      whatever berry with PnP can offer
- [x] Decide whether a pnpm project's section still says `npm`
- [x] `readNpm`'s branch for these two stops naming this item
- [ ] Watched in the app on a real pnpm project and a real yarn project, with
      a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` says pnpm and yarn are among the kinds that are
      read
