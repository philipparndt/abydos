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

2026-08-17 08:49 — about an hour and a half left

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
- [ ] Watched in the app on a real project, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` says npm is among the kinds that are read
