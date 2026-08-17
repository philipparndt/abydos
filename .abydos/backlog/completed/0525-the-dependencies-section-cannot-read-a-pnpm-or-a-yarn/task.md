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

## The YAML decision, which is what this item was filed to settle

**No YAML dependency. A reader of one block's keys, in about eighty lines.**

513's reason for hand-writing TOML — `Cargo.lock` is generated and *flat* —
plainly does not carry over, which is why this item insisted the argument be
made again. It comes out the same way on a different reason:

- **What the section wants out of `pnpm-lock.yaml` is the keys of one block.**
  `packages:` is what was resolved. `importers:` above it is the ranges
  somebody wrote — `^4.17.21`, which is not a version anybody has on disk — and
  is not read. `snapshots:` below it repeats every one of those keys with the
  peers it was built against and the graph beneath it, and *must* not be read
  or the project is drawn twice. So the nesting a YAML library would earn its
  keep on is nesting this reader is required to skip. The only value it looks
  at is the one-line flow mapping after `resolution:`.
- **The file is machine-written and never hand-edited.** pnpm dumps it through
  `js-yaml` with fixed options, so the constructs a hand-written reader is bad
  at — anchors, tags, block scalars, a flow sequence spanning lines — are
  constructs that do not occur in it. Three real lock files on this machine, in
  two layouts, were read to check that rather than assumed.
- **Cost.** Yams is the library, it vendors libyaml, and it would build a
  twenty-thousand-line document — most of it `snapshots:` — to be asked for two
  thousand keys, on a path that runs when a project opens and again on every
  write of the lock file. `project.md` asks for a reason that survives being
  written down; "one block's keys, out of a generated file" is not one.

What a hand-written reader can actually get wrong is a file it does not
understand coming out as `.packages([])`, which draws as *this project depends
on nothing* — the one claim the whole section exists to prevent. So that is
paid for explicitly: a `pnpm-lock.yaml` with no `lockfileVersion` and a
`yarn.lock` with neither of yarn's two headers say they could not be read.
`readConanPackages` made the same move for a Conan 1 lock, and this is that
guard in two more spellings.

## The yarn decision: two syntaxes, and the third is a version number

The item said three formats. It is **two**, and both are read:

- **yarn 1's own file** — a header naming one or more ranges, then indented
  fields, with `version "4.17.21"` and `resolved "…"` quoted by a space.
- **berry's YAML** — everything since yarn 2, with `__metadata`,
  `version: 4.17.21` and `resolution: "lodash@npm:4.17.21"`.

The third "format" in the item's telling is berry's `__metadata.version`, which
has been 4, 5, 6 and 8. Neither of the two fields this reads changed across
them, so there is nothing there to tell apart. And the two syntaxes are the
same *shape* — an entry at column zero, fields indented under it — so one
reader covers both and yarn's is shorter than pnpm's rather than longer.

**What is deliberately not covered: reading inside a Plug'n'Play zip.** A berry
project with the pnp linker has no `node_modules` at all; its packages are zips
under `.yarn/cache`. Those rows name the archive and cannot be opened, which is
exactly 0515's `artefact` — a jar is not a directory either — so this needed no
new state at all. Browsing the inside of a zip is a different capability and
not this item's.

## What was found on the way

The pictures are in `images/`. A pnpm project's section is headed
`Dependencies — pnpm` and a yarn project's `Dependencies — yarn`, over 241 and
890 rows respectively, read from copies of two real projects on this machine.

- **yarn 1 hangs the tarball's sha1 off the end of `resolved`.** npm never
  does, and `npmOrigin` reads a `#` as *this came from a repository and the
  fragment says which revision* — which is right for npm and gave every row of
  every yarn 1 project a whole tarball URL where the registry belongs. Found by
  a test, not by reading, and it would have spoiled 883 rows out of 883.
- **The last `@` in a pnpm store directory is inside the peer.** The store
  holds `@babel+helper-module-transforms@7.25.2_@babel+core@7.25.2`, and
  splitting at the last `@` names a package after what it was built against.
  The `@` that matters is the first one past a leading `@scope/`, which is now
  one function used by both readers.
- **A pnpm lock records no registry at all** for an ordinary package — the
  resolution is an integrity hash and nothing else — so a pnpm project's rows
  carry a version and no origin. That is 514's answer for a `package-lock.json`
  with no `resolved`, and it looks worse than it is: measured on a real
  project, 0 of 234 rows have an origin. The alternative was printing
  `npmjs.com` on all of them, which would be a claim nobody wrote down and
  would be wrong for anybody behind a private registry.
- **The cost is affordable and was measured.** A real pnpm 9 project: 234
  packages against a store of 200 directories, 29 ms warm for the whole
  section. A real yarn 1 project: 883 packages, 40 ms, of which 22 ms is
  parsing the lock and 6 ms is the 96 manifests read to settle which version
  the hoisted copy is.
- **The app restores its own session over what `--open` asked for**, which is
  the hazard 0522 is about. One capture run came back showing a project under
  `~/.config` rather than the scratchpad copy. Nothing was typed and nothing
  was written, but it is worth knowing that a capture run has to be checked
  rather than trusted. `--sidebar-shot` also draws nothing at all unless
  `--screenshot` is passed beside it, which is what `isScreenshotRun` gates.

## Ruled out

- **A YAML dependency.** The argument is above, at length, because the item
  asked for it in writing either way.
- **Reading `.npmrc` to fill in pnpm's missing registry.** It is on disk and it
  is one small file, so it is tempting. It says what the *next* install would
  use, not what this one did — a repository whose registry moved last month
  would have every row claiming the new one. 514's "a row claiming an origin
  nobody wrote down" covers it.
- **Three kinds — `npm`, `pnpm`, `yarn`.** `DependencyKind` is keyed off marker
  files and `package.json` is the marker for all three, so `kinds(at:)` would
  return three sets for every JavaScript project and two of them would say
  nothing. That is 508's empty list wearing three headings. The kind stays one
  and its *title* is read off the lock file, once, when the section is read —
  not while it is drawn, because a tooltip costing four `stat`s per hover is
  the rule this file is written against.
- **Following the symlinks at the top of `node_modules` for pnpm's sources.**
  `node_modules/<name>` is a link into the store and looks like the obvious
  answer. It exists only for a project's *direct* dependencies, and it points
  at one version of a package the lock file may hold three of. The store's own
  `.pnpm/<name>@<version>/node_modules/<name>` is a real directory, so nothing
  has to follow a link and every version has its own.
- **Reproducing pnpm's peer-suffix escaping.** The store directory carries the
  peers after an underscore and pnpm's spelling of them has moved between
  releases. Listed and matched instead — cargo's registry hash and Bazel's
  separator for the third time in this file.
- **Reading every package's `package.json` to place yarn's sources.** A
  `yarn.lock` records no paths, unlike npm's, so something has to say which
  version the copy at `node_modules/<name>` is. Reading all 883 was rejected on
  cost and reading none would have lost the sources of a tenth of the rows; the
  96 names the lock resolves more than once are read, and cost 6 ms.
- **Walking `node_modules` to find yarn's *nested* copies.** A name resolved
  twice has one copy at the root and the rest under whoever needed them, and
  the lock does not say where. Those rows have no sources rather than a guess.
  514 ruled out walking `node_modules` on cost and the answer has not changed.
- **Dropping `patch:` entries by their protocol.** yarn writes a patched
  package twice — once as the entry it patches and once as the patch — so the
  obvious fix is to drop the second. It would lose a package reachable *only*
  through its patch, so the pair is collapsed by name and version instead. Two
  *different* versions of one package stay two rows, the way npm's nested
  copies do.
- **`pnpm list` / `yarn info`, and any other subprocess.** The rule on
  `ExternalDependencies` already covers it, and it is `npm ls` in two more
  spellings: a node launch per project on open, answering with whichever tool
  is first on the PATH, which on this machine is `fnm`'s.
- **Adding a pnpm or yarn fixture to `abydos-examples`.** 513's and 514's
  argument unchanged: `node_modules` is per-machine, cannot be committed, and
  is 140 MB and 262 MB for the two projects photographed here. The claims are
  made by lock files written into temporary directories, and the app was
  watched against scratchpad copies of two real projects.

## Estimate

2026-08-17 15:05 — the work is done; the spec is folded and the branch pushed

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
- [x] Watched in the app on a real pnpm project and a real yarn project, with
      a screenshot
- [x] Write down here what was ruled out on the way
- [x] `spec/project-view.md` says pnpm and yarn are among the kinds that are
      read
