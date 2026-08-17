# 514. The dependencies section cannot read an npm project

Item 508 gave the project view a **Dependencies** section: the packages a
project depends on, named rather than pathed, each with where it came from and
its sources on disk so a file opened by following a symbol can be revealed
beside its siblings.

508 taught it Swift packages and Go modules and left the rest saying so out
loud. A `package.json` project's row in the section reads

    npm — not read yet (0511)

which is this item.

## What it takes

- `package-lock.json` is JSON and names every package with its `version`,
  `resolved` URL and `integrity`. `JSONSerialization` reads it with no
  dependency and no subprocess — the same route `Package.resolved` takes.
- The sources are `node_modules/<name>`, which is *inside the project*. That is
  the case none of the other kinds have and the one worth thinking about: a
  package's files are already reachable in the ordinary tree, under a folder
  the navigator tints as excluded. 508 decided the same question for `.build`
  and the answer was to leave the directory alone and let the Dependencies
  section win a reveal — see that item, and keep the answer the same unless
  there is a reason not to.
- `pnpm` and `yarn` have their own lock files (`pnpm-lock.yaml`,
  `yarn.lock`) and their own layouts — pnpm's `node_modules` is a tree of
  symlinks into `.pnpm`. Deciding whether this item covers all three or only
  npm is the first thing to settle; a lock file that is not read should keep
  saying so rather than fall back to listing `node_modules` and calling the
  result resolved.
- A workspace (`workspaces:` in `package.json`) hoists dependencies to the
  root and is the common shape in a monorepo. The section already groups by
  subproject, so the question is only which root a hoisted package is filed
  under.

## Where the work goes

`Sources/AbydosKit/Project/ExternalDependencies.swift` — one `case npm` in
`DependencyKind` and one reader beside `readSwiftPackages` and
`readGoModules`. The section, the reveal and the sibling browsing are already
built and kind-agnostic.

## Estimate

2026-08-17 09:02 — about half an hour left

## What was read before anybody started, and not verified

An agent read the ground and stood down without writing code. None of it has
been near a compiler.

**The lock file's own keys are the paths.** `package-lock.json` v2 and v3 have a
top-level `packages` object **keyed by path relative to the project root** —
`""` for the project, `node_modules/lodash`, `node_modules/@types/node`,
`node_modules/jest/node_modules/chalk` for a nested conflicting copy,
`packages/app` for a workspace member. **That key is the `localPath`**, which
makes npm the only kind so far needing no cache locator at all. The name is
everything after the *last* `node_modules/`, one rule that gets scopes and
nested copies both right. Values carry `version`, `resolved`, `integrity`,
`dev`, `link`. Version 1 has no `packages` — a recursive `dependencies` tree
keyed by name; v2 has both and `packages` should win. `npm-shrinkwrap.json` is
the same format byte for byte and npm prefers it, and it is **not** in
`definingFileNames`, so writing one would not reload the section.

**Two entry kinds to drop**, both for 0508's "what it lists is what came from
outside": `link: true` entries, which are workspace members symlinked into
`node_modules` with an in-project `resolved`; and any key with no
`node_modules/` in it. Everything else is external, including a member's
non-hoisted copies at `packages/app/node_modules/foo` — filed under the root
that owns the lock file, because that is the only root that parses one. The
member's own row then needs 0513's workspace treatment or it says something
false.

**Origin wants the host, not the tarball.** `resolved` is
`https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz`, and `shortOrigin`
renders that as `registry.npmjs.org/lodash/-`, which is noise on eight hundred
rows. `npmjs.com` for the default registry on 0513's `crates.io` precedent, the
bare host otherwise (`npm.pkg.github.com`). `registry.yarnpkg.com` is a mirror
of the same registry — 0513's "two spellings of one registry" again. A
`git+ssh://…#sha` should keep itself, since `shortOrigin` already cuts it to the
owner. No `resolved` means bundled: empty origin, which `DependencyNode.subtitle`
already renders as version-only.

**`node_modules` needs no code.** It is already in
`FileNode.defaultExcludedDirectoryNames`, `reveal(urls:)` already tries
`dependencies?.locate(url)` before the ordinary tree, and `Subprojects.skipped`
already contains it, so the thousand `package.json` files under it do not
become subprojects.

**Why pnpm and yarn are a separate item, which is the decision this one asks
for.** `package.json` is the marker for all three tools, so a pnpm or yarn
project reaches this reader and would be told to run `npm install` — a
suggestion to install a second, conflicting tree over somebody's project, which
is 0513's workspace-member lie in a new spelling. But reading them is a
different job: `pnpm-lock.yaml` is nested YAML and yarn v1 is a bespoke format
while berry's is YAML, and there is no YAML reader here — 0513's "there is no
TOML reader" again. pnpm's `node_modules` is symlinks into
`.pnpm/<name>@<version>/node_modules/<name>`; yarn berry with PnP has no
`node_modules` at all, only zips under `.yarn/cache`, so there may be nothing to
browse. The plan suggested: know all four names, read npm's two, and have the
others say `pnpm-lock.yaml — not read yet (NNNN)`.

**Cost.** A real `node_modules` is ~1500 entries, so a `fileExists` per entry on
open and again on every write of the lock file — the same shape as the per-pin
stat in `readSwiftPackages`, and worth a comment either way.

## The decision: npm here, pnpm and yarn in 0525

Only npm is read here. pnpm and yarn are **0525**, filed by this item, and the
argument is the stood-down agent's:

- `package.json` is the marker for all three tools, so a pnpm or a yarn project
  reaches this reader whatever it does. Saying nothing is not an option — the
  row would read `no package-lock.json — run npm install`, which tells somebody
  to install a second, conflicting tree over a project that is already
  installed. That is 513's workspace-member lie in a new spelling, and it is
  worse, because the suggestion here writes hundreds of megabytes.
- Reading them is a different job rather than a longer one. `pnpm-lock.yaml` is
  nested YAML and yarn berry's is YAML too, and there is no YAML reader in this
  repository — 513's "there is no TOML reader" again, but without 513's answer,
  since neither file is flat enough for thirty lines. yarn v1 is a third,
  bespoke format. pnpm's `node_modules` is symlinks into `.pnpm`, and yarn
  berry with PnP has no `node_modules` at all, only zips.

So this item knows all four lock file names and reads npm's two. The other two
say which tool resolved the project and name 0525, which is the same sentence a
kind nothing reads yet says, in a place `DependencyKind` cannot reach — the
kind *is* read, and it is this one root that it cannot answer for.

## What was found on the way

The pictures are in `images/`. An npm project's section reads

    Dependencies — npm
      @electron/get   1.12.4  ·  npmjs.com
      fs-extra        9.1.0   ·  npmjs.com
      fs-extra        7.0.1   ·  npmjs.com
      fs-extra        4.0.3   ·  npmjs.com
      …

— 207 packages out of a real `package-lock.json`, and `fs-extra` three times
because three packages in that project want three different versions of it.
Opening `node_modules/@electron/get/node_modules/fs-extra/lib/index.js` reveals
on the *middle* of those three rows, with `CHANGELOG.md`, `LICENSE`,
`package.json` and `README.md` beside it. Nothing was written for that: 508's
rule that a package row is a directory did all of it, and the key in the lock
file was the directory.

### Every finding in "what was read before anybody started" held

It had not been near a compiler, and it turned out to be right about all of it:
the `packages` keys are paths and are the `localPath`; the name is everything
after the last `node_modules/`; `link: true` and the keys with no
`node_modules` in them are exactly the entries to drop; `node_modules` needed no
code in the navigator, the reveal or `Subprojects`. Two things it did not have:

- **`resolved` is missing far more often than "bundled".** The plan expected an
  absent `resolved` only for a bundled dependency. One of the npm projects on
  this machine has **990 entries of 992** without one — a whole tree installed
  through something that did not write the field. Those rows are version-only,
  which the row already draws, and a reader that had assumed `resolved` would be
  there would have dropped that project's entire list.
- **A git dependency and a registry tarball are both `https://` once `git+` is
  gone**, and the host is the right answer for exactly one of them.
  `github.com` alone, on a row, says a package came from GitHub and not which
  repository — so the `git+` prefix, a `git://` scheme or a `#revision` is what
  keeps the whole URL. Found by a test, not by reading.

### The cost, measured

992 entries, 7.4 ms warm, on a real project — `fileExists` per package, paid on
open and on every write of the lock file. Small enough that the alternative
(walking `node_modules`, which is where npm's reputation comes from) was never
worth considering.

### The pnpm and yarn rows are the item's real product

A pnpm project and a yarn project both reach this reader, because
`package.json` is the marker for all three tools. They now read

    resolved by pnpm — pnpm-lock.yaml not read yet (0525)
    resolved by yarn — yarn.lock not read yet (0525)

rather than `no package-lock.json — run npm install`, which is an instruction
that would have installed a second, conflicting tree over a working project.
The section heading over those rows still says `npm`, because the kind is keyed
off `package.json` and all three tools use it; 0525 has the question of whether
that becomes three kinds.

## Ruled out

- **`npm ls --json`, and any other subprocess.** It answers everything at once
  and it is `cargo metadata` and `swift package dump-package` in a third
  spelling: a node launch per project on open and again on every write of the
  lock file, on a synchronous path, answering with whichever npm is first on the
  PATH — which on this machine is `fnm`'s, so the answer depends on which shell
  last ran. The lock file is the resolved tree and is already on disk.
- **Reading `node_modules` instead of the lock file.** It is the one kind where
  the sources are *inside* the project, so listing the directory looks tempting
  and is wrong twice: a directory listing has no version, no origin and no way
  to tell a package from a leftover, and walking ~1500 directories on open
  costs orders of magnitude more than 992 stats.
- **Reading `package.json` for the dependency names.** It says `^4.17.21`, which
  is not a version anybody has on disk, and it does not know the transitive
  ones. 513 ruled the same thing out for `Cargo.toml` and it is the same
  argument.
- **Marking a package `dev`, or direct against transitive.** The lock file has
  `dev: true` and the root's own `dependencies` map, so both could be computed.
  Not done, for 508's reason: one list sorted by name is what makes eight
  hundred rows browsable, and "what is beside this file" is not answered by how
  the package was reached. The fields are parsed by nothing, so it is a few
  lines if somebody wants it.
- **De-duplicating the nested copies.** `fs-extra` appears three times in the
  picture, at three versions, from three keys. That is what the project has, and
  collapsing them to one row would name a version the file in somebody's tab is
  not from. The one cost is that `DependencyNode.identity` is
  `package:<origin>:<name>`, so the three share an identity and the tree's
  expansion state cannot tell them apart — cosmetic, and in `DependencyTree`,
  which 0515 and 0516 are also editing around, so it is left where it is.
- **Naming the origin after the tarball host as written.**
  `registry.npmjs.org/lodash/-` is what `shortOrigin` makes of a `resolved` URL
  — three quarters noise, repeated on every row. `npmjs.com` on 513's
  `crates.io` precedent, and `registry.yarnpkg.com` reads as the same registry,
  which it is.
- **Treating any ancestor with a lock file as a workspace.** The first version
  did, and it would have told a `docs` folder with a `package.json` of its own —
  inside a repository that is not a workspace — that it was "resolved in the
  workspace at …", which is false. The ancestor has to declare `workspaces` (or
  have a `pnpm-workspace.yaml`); a project that genuinely has not been installed
  is still told to install.
- **Adding an npm fixture to `abydos-examples`.** 513's argument, unchanged and
  stronger: `node_modules` is per-machine, cannot be committed, and is 30 MB for
  the small project photographed here. The examples repository is built to
  compile offline. The claims are made by lock files written into temporary
  directories, and the app was watched against a copy of a real project with its
  real `node_modules`.

## Steps

- [x] Read `package-lock.json` into packages: name, version, origin
- [x] The sources are `node_modules/<name>`, and a package not installed says
      nothing rather than pointing at a directory that is not there
- [x] Decide whether pnpm and yarn are in this item or their own, and write the
      answer down
- [x] File the item that will read the lock files this one does not
- [x] A pnpm or a yarn project says which tool resolved it, rather than being
      told to run `npm install`
- [x] Decide which root a hoisted workspace dependency is filed under
- [x] A workspace member says where its lock file is, rather than that there is
      none
- [x] The version 1 lock layout is still read, the way both layouts of
      `Package.resolved` are
- [x] `DependencyKind.pendingItem` stops naming this item for npm
- [x] Watched in the app on a real project, with a screenshot
- [x] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` says npm is among the kinds that are read
