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

## What was found on the way

The pictures are in `images/`. A Cargo project's section now reads

    Dependencies
      rustproj — Cargo
        anyhow        1.0.104  ·  github.com/dtolnay
        proc-macro2   1.0.107  ·  crates.io
        serde         1.0.229  ·  crates.io
        …
      helper — Cargo
        resolved in the workspace at rustproj

and `serde` opens into its own files, out of the registry cache, so a file
opened from `~/.cargo/registry/src/…/serde-1.0.229/src/lib.rs` is revealed on
that row with its siblings beside it. Nothing was written for that: 508's rule
that a package row *is* a directory did all of it.

### The workspace member was saying something false, and only the app said so

The first real Rust project it was pointed at had a path dependency, `helper`,
which is therefore a subproject, which therefore has a row — and the row read
`no Cargo.lock — run cargo fetch`. Which is a lie in the shape of a helpful
suggestion: a workspace has exactly one lock file, at its root, and running
`cargo fetch` inside a member writes nothing there. Nearly every Rust
repository of any size is a workspace, so this would have been the commonest
row this reader ever drew. It now says `resolved in the workspace at <root>`,
found by walking up for a directory with both a `Cargo.toml` and a
`Cargo.lock`.

The workspace's list is deliberately *not* borrowed down into the member. It is
the whole workspace's resolved set, not that crate's, and five members would
each have shown all two hundred packages and claimed them.

### The empty state is real but nearly unphotographable

`no Cargo.lock — run cargo fetch` had to be caught at 2.6 seconds after launch,
because rust-analyzer starts, runs `cargo metadata`, and **writes the lock file
itself** — `Cargo.lock` is in `definingFileNames`, the watcher fires, and the
row becomes eight packages. Two things follow. The message is right, since the
state it names is genuine on a fresh checkout with no language server running.
And the rule about subprocesses is not an aesthetic one: the resolving is
expensive enough that the one component that does do it does it in the
background, out of process, and takes seconds over it.

### No new fixture in `abydos-examples`, and why

There is already a Cargo project there — `native/rust-hello` — and it depends
on nothing, which is a state worth having: it draws `no dependencies`, one of
the section's three answers. What it cannot show is packages, and giving it a
dependency would not fix that: the registry cache is per-machine and cannot be
committed, so a fixture with `serde` in it says nothing at all until somebody
with a network runs `cargo fetch`. The examples repository is deliberately
built to compile offline — `go-service` and `java/maven-service` both depend on
nothing either, and `cadova-models` is called out in its README as the one
exception that "needs the network once". 0500's precedent is a fixture that is
complete on disk, and a Cargo one cannot be. So the claims here are made by
lock files written into a temporary directory, and the app was watched against
a real project with real crates fetched into a real cache.

### One test in the suite fails, and it is not this branch — 0514–0516 will meet it

`CadovaExampleLiveTests.runsAndWritesAThreeMF` builds
`abydos-examples/cadova-models`, and that working tree has an uncommitted edit
in it:

    -        Circle(diameter: diameter)
    +        C-ircle(diameter: diameter)

A stray `-` typed into somebody's fixture, in the family of 0517 and 0518. The
2712 tests are otherwise green and `make warnings` is clean. Left alone: it is
another repository and not this item's, and reverting somebody's working tree
to make a suite green is the wrong instinct twice over.

## For 0514, 0515 and 0516

The doc comment on `ExternalDependencies.read(root:kind:)` is the list, kept
next to the code it describes rather than here. In short: a `readX(at:)` under
a `MARK` of its own returning `DependencySet.Contents`, sorted with `byName`; a
cache locator beside it if the sources are outside the project (`cargoHome()`
is the shape — the tool's environment variable, then the documented default,
never the tool); the `case` in the switch; **`pendingItem` stopping at that
kind**, or the row goes on saying "not read yet" over a list it is reading; and
any lock file in `definingFileNames`. Three things this item learned that the
next three will meet in their own spelling:

- **`.unresolved` is not one state.** "Nothing has resolved this yet" and "this
  is resolved somewhere else" are different sentences and the second one is the
  common case in a monorepo. npm has workspaces, Gradle has subprojects, Maven
  has modules with a parent `pom.xml` — all four of you have this.
- **The cache directory name is not always computable.** Cargo hashes the
  registry URL with a function it does not document. List and match rather than
  build a path and hope.
- **Watch the reader in the app before believing it.** Seventeen tests passed
  over the workspace-member lie, and the app showed it in the first ten
  seconds. That was 508's finding too.

## Ruled out

- **A TOML library.** `Cargo.lock` is generated, never hand-written, and is a
  flat sequence of `[[package]]` tables of quoted strings — no nesting, no
  dates, no multi-line strings, nothing a parser earns its keep on.
  `project.md` asks for an argument before a dependency is added, and "one
  generated file, four keys" is not one. Thirty lines, the same call
  `SwiftPackage` made about `Package.swift` and `readGoModules` about `go.mod`.
  The one trap it does have is written down in the code: the
  `dependencies = [ … ]` array under a package holds bare strings, and in the
  version 1 and 2 lock layouts those are whole package ids with
  `git+…?branch=main#sha` inside them — split every line on its first `=` and
  that fragment is read as a key of the table.
- **`cargo metadata`.** It answers manifest and lock in one call, and it is
  `swift package dump-package` with a different name: a subprocess on a
  synchronous path run once per directory and again on every write, whose
  toolchain is whatever is first on the PATH, and which *writes a lock file*
  into somebody's project as a side effect of being asked. Watching
  rust-analyzer do exactly this to a fresh project, and take seconds over it,
  is the measurement this item did not have to take.
- **Naming the origin after the registry index.** `registry+https://github.com/
  rust-lang/crates.io-index` cut down by `shortOrigin` is `github.com/rust-lang`,
  which reads as *this crate came from that repository* and would say it on
  every row of a list of two hundred. The row says `crates.io`. A registry that
  is not crates.io keeps its URL, because there the host is the answer.
- **Listing path dependencies and workspace members.** They have no `source` in
  the lock file, they are directories inside the project, and the tree already
  has rows for them. An *external* section listing them would show the
  project's own source twice under a heading saying it came from outside.
- **Reading `Cargo.toml` for the dependency names.** It says `serde = "1"`,
  which is not a version anybody has on disk, and it does not know about the
  transitive ones. The lock file is the resolved graph and is the whole point.
- **Marking a crate direct or transitive.** `Cargo.lock` has the edges — every
  package's `dependencies` array — so unlike Go this could be computed rather
  than read off a comment. Not done, for 508's reason: one list sorted by name
  is what makes thirty rows browsable, and "what is beside this file" is not
  answered by resolution order. The edges are parsed by nothing, so if somebody
  wants a graph later it is four more lines.
- **Adding a Cargo example to `abydos-examples`.** Above.

## Estimate

2026-08-16 21:46 — about half an hour left

## Steps

- [x] Read `Cargo.lock` into packages: name, version, origin
- [x] Find the sources in the registry cache, and say nothing rather than
      guessing when they are not fetched
- [x] A git dependency's checkout is found too, under `~/.cargo/git/checkouts`
- [x] A path dependency is not an external dependency, and is left out
- [x] `DependencyKind.pendingItem` stops naming this item for Cargo
- [x] Say what a new kind has to implement, where 0514–0516 will look for it
- [x] A member of a workspace says where its lock file is, rather than that
      there is none — found in the app, on the first real Rust project
- [x] Decide whether a Cargo project belongs in `abydos-examples`, and say which
- [x] Watched in the app on a real Rust project, with a screenshot
- [x] Write down here what was ruled out on the way
- [ ] The spec says Cargo is among the kinds that are read —
      `spec/project-view.md`, which is where 508 put the section (the item said
      `editor.md`, which was written before that capability existed)
