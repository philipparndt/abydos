# 513. The dependencies section cannot read a Cargo project

Item 508 gave the project view a **Dependencies** section: the packages a
project depends on, named rather than pathed, each with where it came from and
its sources on disk so a file opened by following a symbol can be revealed
beside its siblings.

508 taught it two kinds — Swift packages and Go modules — and left the rest
saying so out loud rather than showing nothing. A Cargo project's row in the
section reads

    Cargo — not read yet (0510)

which is this item. Until it is done, a Rust project's dependencies are visible
in the app as *missing*, which is the whole point of the note, but they are
still missing.

## What it takes

- `Cargo.lock` is TOML and names every package: `name`, `version`, `source`,
  `checksum`. It is the resolved graph and it is on disk, so no subprocess —
  the same rule `SwiftPackage` and `Package.resolved` follow.
- Sources are in the registry cache, `$CARGO_HOME/registry/src/<registry>/<name>-<version>`,
  with `CARGO_HOME` defaulting to `~/.cargo`. The registry directory has a hash
  in its name (`index.crates.io-<hash>`), so it has to be listed rather than
  computed.
- A path dependency (`source` absent) is inside the project already and should
  probably not be listed as external at all; a git dependency's checkout is in
  `~/.cargo/git/checkouts/…`.
- There is no TOML reader in this repository. `Cargo.lock` is a flat sequence
  of `[[package]]` tables with string values and needs about thirty lines of
  line-by-line parsing, not a TOML library — the same choice `SwiftPackage`
  made about `Package.swift`. Adding a dependency for this would need the
  argument `project.md` asks for and it does not have one.

## Where the work goes

`Sources/AbydosKit/Project/ExternalDependencies.swift` — one `case cargo` in
`DependencyKind`, one reader function beside `readSwiftPackages` and
`readGoModules`, and the note disappears on its own. The section, the reveal
and the sibling browsing are already built and kind-agnostic.

`Tests/AbydosKitTests/ExternalDependenciesTests.swift` has the shape to copy:
a fixture lock file written into a temporary directory, and a claim about what
comes out.

## Steps

- [ ] Read `Cargo.lock` into packages: name, version, origin
- [ ] Find the sources in the registry cache, and say nothing rather than
      guessing when they are not fetched
- [ ] A path dependency is not an external dependency, and is left out
- [ ] Watched in the app on a real Rust project, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says Cargo is among the kinds that are read
