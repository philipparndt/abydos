# 511. The dependencies section cannot read an npm project

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

## Steps

- [ ] Read `package-lock.json` into packages: name, version, origin
- [ ] The sources are `node_modules/<name>`, and a package not installed says
      nothing rather than pointing at a directory that is not there
- [ ] Decide whether pnpm and yarn are in this item or their own, and write the
      answer down
- [ ] Decide which root a hoisted workspace dependency is filed under
- [ ] Watched in the app on a real project, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says npm is among the kinds that are read
