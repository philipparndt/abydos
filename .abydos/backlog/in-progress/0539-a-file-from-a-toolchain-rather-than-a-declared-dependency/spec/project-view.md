## ADDED Requirement: A compiler's own sources have a row, once somebody goes there

Every reader behind **Dependencies** answers one question: what did this
project declare, and what did that resolve to. A toolchain's own sources are an
answer to nothing — no manifest names them, they arrive with the compiler — so
`time.go` from Go's `src/time` fell out of that model rather than being
mishandled by it: the file opened, and nothing in the tree could reveal it.

A toolchain gets a row of its own **under Dependencies**, beside the packages,
after them. IntelliJ's *External Libraries* holds the JDK, so there is
precedent; the reasons are that reveal has exactly one section that wins over
the ordinary tree and a second one would be a second rule about which root
claims a file, that the section is "what the project is made *from*" and a
compiler is that, and that a root of its own would be an empty row on every
project that has never been navigated out of. What the heading might be taken
to claim, the row denies on its face: its grey half reads `go1.26.6 ·
toolchain` rather than a version and a registry.

**Where the toolchain is comes from the path, not from a question.** The rule
that nothing runs a build tool to fill this section holds, and `go env GOROOT`
would break it. Nor is it guessed from `$GOROOT` or a default under the home
directory, the way the module caches are: this runs when a file has already
been opened and its path is in hand, so the toolchain root is read out of the
answer the language server gave — the ancestor of that file which holds a
`VERSION` beginning `go` beside a `src`, or the ancestor named `*.sdk` which
holds an `SDKSettings.json`. A machine with three Go installations gets the one
the file actually came from.

The cost, and it is the honest one: **a toolchain has no row until somebody has
been into it.** A freshly opened project has no `Go standard library` row,
because a row for a toolchain nobody has visited would be this program guessing
which compiler the project is built with.

The row is a directory, like a package's, so nothing walks it: an SDK's headers
are tens of thousands of files and none is read until the row is opened. Go's
row is rooted at `src`, whose children are the standard library's packages, and
an SDK's at the `.sdk` itself, because its headers, its frameworks and its
Swift modules are in three different places under it.

Two of the four kinds of toolchain are read. **A JDK is not**: jdtls answers
with `jdt://` URIs, and where it does name a file it is an entry inside
`src.zip` — nothing here reads an archive, and a row rooted at a zip would be a
folder holding one binary file. **The Swift standard library is not**, and for
a different reason: what sourcekit-lsp hands back for `String` is not a file in
the toolchain but a generated interface, behind a URI this program cannot open
or written into a scratch directory for the occasion, so there is nothing with
siblings to root a row at. Where the Swift sources genuinely are inside an
`.sdk`, the SDK's row already holds them.

### Scenario: following a symbol into the Go standard library

- **Given** a Go module whose `go.mod` requires nothing
- **When** a symbol is followed into the toolchain's own `src/time/time.go`
- **Then** `Dependencies` still reads `no dependencies` for that module, which
  is the truth about its `go.mod`
- **And** beside it there is a `Go standard library` row reading
  `go1.26.6  ·  toolchain`
- **And** the file is selected under it, with the rest of `time` beside it

### Scenario: a system header

- **Given** a file opened from inside an SDK — `MacOSX.sdk/usr/include/stdio.h`
- **Then** the section has a `macOS SDK` row reading `27.0  ·  SDK`
- **And** the header is revealed under it

### Scenario: a toolchain nobody has been into

- **Given** a project just opened, whatever is installed on the machine
- **Then** there is no toolchain row

### Scenario: opening the row

- **Given** a `Go standard library` row
- **When** it is opened
- **Then** its children are the standard library's packages — `time`, `fmt`,
  `net` — rather than the distribution's `api`, `bin`, `pkg` and `test`
- **And** nothing under it was read before it was opened

### Scenario: a directory that merely looks like one

- **Given** a project holding a `src` directory, and a `VERSION` file beside it
  that is not a Go version
- **Then** it is not a toolchain, and gets no row

## MODIFIED Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one — until a symbol is followed out of it into a
compiler's own sources, which is something to show and so is shown.

The list is read from what is already on disk. Nothing runs a build tool to
answer it — not `swift package dump-package`, not `cargo metadata`, not `mvn
dependency:list`, not `npm ls`, not `go env`, and not Gradle, which was
expected to be the kind that forced the rule and turned out to be the kind that
needs it least. That holds even where the build tool is the obvious way to ask:
Conan's recipe is a Python program and evaluating it would be running somebody's
code to fill in a tree row, and `bazel query` starts a server that takes a lock
on the output base, which would leave this section and somebody's build waiting
on each other.

Where one marker file belongs to several tools, the section is named after the
tool that did the resolving rather than after the marker. `package.json` is
npm's, pnpm's and yarn's alike, and the lock file beside it says which of the
three installed this project; a project holding more than one is answered by
npm's own order of preference, so two readings of it agree.

What it lists is what came from outside. A dependency that is a directory
inside the project — a Cargo `path` dependency, an npm workspace member, a
pnpm `file:` dependency, a yarn `workspace:` or `link:` entry, a Gradle
`project(":common")`, the project's own crate — has a row in the tree already,
and listing it again under a heading that says it came from elsewhere would
show the same source twice. Where a package came from is a question about the
lock file and not about where its files sit: an npm package's sources are
inside the project, under `node_modules`, and it is still a dependency.

### Scenario: a Swift package with its dependencies resolved

- **Given** a project with a `Package.resolved`
- **When** the project is opened
- **Then** the tree has a `Dependencies` row under the project's own files
- **And** it holds one row per package in `Package.resolved`

### Scenario: a Cargo project

- **Given** a project with a `Cargo.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per crate the lock file resolved

### Scenario: an npm project

- **Given** a project with a `package-lock.json`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per package the lock file resolved
- **And** a package installed twice at two versions, because two packages
  needed different ones, has a row for each

### Scenario: a pnpm project

- **Given** a project with a `pnpm-lock.yaml`
- **When** the `Dependencies` row is opened
- **Then** the section is headed `pnpm` rather than `npm`
- **And** it holds one row per package the lock file's `packages` block
  resolved, each with the version on disk
- **And** a package named a second time under `snapshots`, once per set of
  peers it was built against, still has one row

### Scenario: a yarn project

- **Given** a project with a `yarn.lock`, in either the yarn 1 syntax or the
  YAML one every yarn since 2 writes
- **When** the `Dependencies` row is opened
- **Then** the section is headed `yarn`
- **And** it holds one row per package the lock file resolved

### Scenario: a project installed by two tools

- **Given** a project with both a `package-lock.json` and a `yarn.lock`
- **Then** the section is headed `npm`, and reads the same on every opening

### Scenario: a Maven project

- **Given** a project with a `pom.xml` declaring three dependencies
- **When** the `Dependencies` row is opened
- **Then** it holds one row per dependency the POM declares

### Scenario: a Gradle build with its dependencies locked

- **Given** a project with a `gradle.lockfile`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per coordinate the lock file resolved, transitive
  ones included

### Scenario: a Gradle build with no lock file

- **Given** a build file whose `dependencies { }` block names two coordinates
- **Then** both have a row
- **And** a coordinate named inside `buildscript { }` has none, because that is
  the plugin classpath rather than what the project is built from

### Scenario: a crate that is a directory in the project

- **Given** a `Cargo.lock` naming a crate with no source — a `path` dependency
  or a workspace member
- **Then** that crate has no row in `Dependencies`

### Scenario: an npm workspace member

- **Given** a `package-lock.json` naming a member of the workspace, both by its
  path and as a link under `node_modules`
- **Then** that member has no row in `Dependencies`

### Scenario: a yarn workspace member

- **Given** a `yarn.lock` whose entry resolves to `workspace:packages/app`
- **Then** that member has no row in `Dependencies`

### Scenario: a Bazel workspace

- **Given** a project with a `MODULE.bazel.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per module the lock file selected
- **And** a module the lock merely *considered* — an older version whose
  `MODULE.bazel` was fetched to compare it and whose `source.json` was not — has
  no row, so one module never shows as three

### Scenario: a Bazel workspace nobody has built

- **Given** a project with a `MODULE.bazel` and no lock file
- **When** the `Dependencies` row is opened
- **Then** it holds one row per `bazel_dep` the manifest declares

### Scenario: a Conan project

- **Given** a project with a `conan.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per package the lock file resolved
- **And** the recipe is not executed to find them

### Scenario: a directory with no build system in it

- **Given** a project with no manifest of any kind
- **When** the project is opened
- **Then** there is no `Dependencies` row

## MODIFIED Requirement: A file with no place in the tree is revealed in the section

A package row is a directory, so the rows beneath it are the package's own
files and everything the tree does with a file it does with them: they list
lazily, they open, and the arrow keys walk them. A toolchain's row is the same
shape, and everything here is true of it too.

A file opened from inside a package — by following a symbol out of the
project's own code, or by being named on the command line — is revealed there,
with the section and every folder above it opened and the file selected. That
holds for every copy of a checkout this machine has: `swift build` fetches into
the project's `.build/checkouts` and the Swift indexer fetches its own copy
beside its index, and a file opened from either lands on the row the section is
showing.

The section wins over the ordinary tree for such a file. A checkout under
`.build` is inside the project and has a row there too, but only the section's
row can say which package the file belongs to and where that package came from.

**And a file the tree genuinely cannot place says so**, when somebody asks for
it to be revealed. Doing nothing was the whole of what a file with no row got
before, and a reveal that lands nowhere is indistinguishable from a reveal that
was never asked for. The sentence says what is true of *that* file — outside
the project and in no package, or inside it and hidden by a filter — rather
than a fixed apology. It is said only when the reveal was asked for: following
the tabs is the same gesture a hundred times an hour and stays silent.

### Scenario: following a symbol into a package

- **Given** a Swift file in the project that uses a type from a package
- **When** the definition of that type is asked for
- **Then** the file opens
- **And** the tree selects it under that package in `Dependencies`
- **And** the folder it is in shows the rest of the package's files beside it

### Scenario: the same file, from the other checkout

- **Given** a file under the project's own `.build/checkouts`
- **When** it is opened
- **Then** it is revealed in `Dependencies` rather than under `.build`

### Scenario: a file that belongs nowhere in this window

- **Given** a file open in a tab, from outside the project and from no package
  or toolchain
- **When** the tree is asked to reveal it
- **Then** it says the file is not in the tree, and why
- **And** switching to that tab says nothing
