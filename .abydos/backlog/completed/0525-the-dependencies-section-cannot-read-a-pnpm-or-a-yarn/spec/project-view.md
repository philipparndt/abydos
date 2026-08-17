<!-- What this item changes about `project-view`. Folded into
     .abydos/backlog/spec/project-view.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     The requirements already there, to name exactly:
       A project shows what it depends on, beside its own files
       A dependency says which version it is and where it came from
       A kind of project this cannot read says so, on a row
       A dependency says which subproject resolved it
       A file with no place in the tree is revealed in the section
       `.build` is an ordinary folder
       A list that is read and incomplete says what is missing
-->

## MODIFIED Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one.

The list is read from what is already on disk. Nothing runs a build tool to
answer it — not `swift package dump-package`, not `cargo metadata`, not `mvn
dependency:list`, not `npm ls`, and not Gradle, which was expected to be the
kind that forced the rule and turned out to be the kind that needs it least.
That holds even where the build tool is the obvious way to ask: Conan's recipe
is a Python program and evaluating it would be running somebody's code to fill
in a tree row, and `bazel query` starts a server that takes a lock on the
output base, which would leave this section and somebody's build waiting on
each other.

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

## MODIFIED Requirement: A dependency says which version it is and where it came from

Each package row carries the version the project resolved and an abbreviation
of its origin — the host and owner of a Swift package's repository, the module
path of a Go module, the registry a crate or an npm package was published to,
the group a Maven or Gradle coordinate names. The whole origin, the version and
the directory the sources are in are on the row's tooltip, which is where
anything too long for the pane goes.

A package that has been resolved and never fetched is still a row. It has no
sources to open, which is a different thing from not being depended on.

A package whose lock file records no origin at all is a row with a version and
nothing else, rather than one claiming an origin nobody wrote down. That is
not a rare case: a `pnpm-lock.yaml` records an integrity hash and no registry
for every ordinary package, so a pnpm project's rows carry an origin only where
the lock names a tarball or a repository. The registry such a package came from
is in somebody's `.npmrc`, which says what the *next* install would use rather
than what this one did, and is not read.

A dependency that resolves to a **file** rather than to sources is a row with
nothing under it, and its tooltip names the file. Two things do this: the JVM,
where Maven and Gradle fetch a jar, and yarn's Plug'n'Play, where a package is
a zip under `.yarn/cache` and there is no `node_modules` at all. A row pointed
at the directory such a file sits in would open onto an archive and a checksum
rather than onto a package. It is a different state from never having been
fetched, and the tooltip says which of the two it is.

### Scenario: a package resolved to a released version

- **Given** a `Package.resolved` pinning `Cadova` at `0.9.1` from
  `https://github.com/tomasf/Cadova.git`
- **When** the `Dependencies` row is opened
- **Then** the row reads `Cadova`, `0.9.1`, `github.com/tomasf`

### Scenario: a package pinned to a branch

- **Given** a pin with a branch and no version
- **Then** the row shows the branch

### Scenario: a crate from crates.io

- **Given** a `Cargo.lock` resolving `serde` at `1.0.229` from the crates.io
  index
- **Then** the row reads `serde`, `1.0.229`, `crates.io`
- **And** it reads the same whether the lock file names the git index or the
  sparse one

### Scenario: a crate from a git repository

- **Given** a `Cargo.lock` resolving `anyhow` from
  `git+https://github.com/dtolnay/anyhow#bf3ed914…`
- **Then** the row reads `github.com/dtolnay`
- **And** the tooltip has the whole source, revision included

### Scenario: an npm package from the registry

- **Given** a `package-lock.json` resolving `lodash` at `4.17.21` from
  `https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz`
- **Then** the row reads `lodash`, `4.17.21`, `npmjs.com`
- **And** a package served from `registry.yarnpkg.com` reads the same, because
  it is the same registry
- **And** a package from any other registry reads that registry's host

### Scenario: a yarn 1 package from the registry

- **Given** a `yarn.lock` whose `resolved` is a registry tarball with the
  file's own sha1 hung off the end of it as a fragment
- **Then** the row reads the registry, not the tarball URL

### Scenario: a yarn package from the registry, in the newer syntax

- **Given** a `yarn.lock` entry resolving to `lodash@npm:4.17.21`
- **Then** the row reads `lodash`, `4.17.21`, `npmjs.com`

### Scenario: an npm package from a git repository

- **Given** a `package-lock.json` resolving a package from
  `git+https://github.com/dtolnay/anyhow.git#bf3ed914`
- **Then** the row reads `github.com/dtolnay`, and not the host alone

### Scenario: a package whose lock file records no origin

- **Given** an entry in a `package-lock.json` with no `resolved`, or a
  `pnpm-lock.yaml` package whose resolution is an integrity hash and nothing
  else
- **Then** the row shows the version and no origin

### Scenario: a pnpm package the lock file does name a source for

- **Given** a `pnpm-lock.yaml` package whose resolution names a tarball on
  another registry
- **Then** the row reads that registry's host

### Scenario: a Maven dependency whose jar has been downloaded

- **Given** a `pom.xml` naming `commons-lang3` at `3.14.0`, whose jar is in the
  local repository
- **Then** the row reads `commons-lang3`, `3.14.0`, `org.apache.commons`
- **And** the row cannot be opened
- **And** its tooltip names the jar rather than saying the dependency was not
  fetched

### Scenario: a package under Plug'n'Play

- **Given** a yarn project with no `node_modules` and the package's zip in
  `.yarn/cache`
- **Then** the row cannot be opened, and its tooltip names the archive rather
  than saying the dependency was not fetched

### Scenario: a version the project does not state

- **Given** a `pom.xml` dependency with no `<version>`, managed by a BOM that
  is not in the project
- **Then** the row has the name and the group and no version, rather than the
  `${…}` or the blank the file holds

### Scenario: a package nobody has fetched

- **Given** a pin whose sources are in no checkout on this machine
- **Then** the package still has a row
- **And** the row cannot be opened

## MODIFIED Requirement: A kind of project this cannot read says so, on a row

The section covers every build system this program opens, whether or not it can
read that system's dependencies yet. A kind it cannot read shows a row saying
so, with the number of the backlog item that will teach it — never an empty
list, which would read as a project that depends on nothing.

**Every kind is read as of 0515 and every JavaScript tool as of 0525**, so this
half of the requirement has no subject: the scenario that stood here named
whichever kind was still waiting. The rule stays written down because it is for
the kind added next, which is the only one that can need it.

A kind it *can* read, in a project that has resolved nothing yet, says that
instead, and says it in the words of the tool that would resolve it. A project
that has resolved nothing because something *above it* did the resolving says
where that was, rather than naming a command that would write nothing here; and
a project whose own job is to hold other projects says that its modules are
where the dependencies are.

A lock file this program cannot make sense of is also said out loud, rather
than being read as a project with no dependencies. That distinction is the one
the hand-written readers are held to: a `conan.lock` written by Conan 1, a
`pnpm-lock.yaml` with no `lockfileVersion` and a `yarn.lock` with neither of
yarn's two headers all say they could not be read, while the same files holding
nothing but a header are a project that genuinely depends on nothing and say
`no dependencies`.

Where no command would resolve it, the row says why instead of naming one. A
suggestion that cannot be followed is worse than none: the row's whole job is to
be believable about what is missing.

Every one of these sentences is longer than the pane is wide, so the whole of
one is on the row's tooltip — the same place a package's unabbreviated origin
goes.

### Scenario: a Swift package that has never been resolved

- **Given** a project with a `Package.swift` and no `Package.resolved`
- **Then** the row reads `no Package.resolved — run swift package resolve`

### Scenario: a Cargo project that has never been resolved

- **Given** a project with a `Cargo.toml` and no `Cargo.lock`
- **Then** the row reads `no Cargo.lock — run cargo fetch`

### Scenario: an npm project that has never been installed

- **Given** a project with a `package.json` and no lock file of any kind
- **Then** the row reads `no package-lock.json — run npm install`

### Scenario: a lock file this program cannot make sense of

- **Given** a `pnpm-lock.yaml` with no `lockfileVersion` in it
- **Then** the row says the file could not be read
- **And** it does not read as a project with no dependencies

### Scenario: a crate that is a member of a workspace

- **Given** a crate with a `Cargo.toml`, no `Cargo.lock` of its own, and a
  workspace above it that has one
- **Then** the row says the crate is resolved in that workspace, and names it
- **And** the workspace's own list is not repeated under the member

### Scenario: a member of an npm workspace

- **Given** a package with a `package.json`, no lock file of its own, and a
  directory above it whose `package.json` declares `workspaces` — or which has
  a `pnpm-workspace.yaml` beside it — and which has a lock file
- **Then** the row says the package is resolved in that workspace, and names it
- **And** the workspace's own list is not repeated under the member

### Scenario: a Conan project that has never been resolved

- **Given** a project with a `conanfile.py` or a `conanfile.txt` and no
  `conan.lock`
- **Then** the row names the command that writes one, which is
  `conan lock create .` and not `conan install`

### Scenario: a lock file from an older version of the tool

- **Given** a `conan.lock` written by Conan 1, which is valid JSON and says none
  of what Conan 2's says
- **Then** the row says so
- **And** it does not read as a project with no dependencies

### Scenario: a Bazel workspace declared in Starlark

- **Given** a project with a `WORKSPACE` and no `MODULE.bazel`
- **Then** the row says its dependencies are Starlark and that nothing on disk
  lists them
- **And** it names no command, because none of them would produce such a file

### Scenario: a note too long for the pane

- **Given** any row of this kind
- **When** it is cut off at the edge of the pane
- **Then** its tooltip has the whole sentence

### Scenario: a Maven POM that only aggregates modules

- **Given** a `pom.xml` with `<packaging>pom</packaging>`, a list of modules and
  no dependencies of its own
- **Then** the row says its modules have the dependencies

### Scenario: a Gradle settings file with no build file beside it

- **Given** a directory with a `settings.gradle` and no `build.gradle`
- **Then** the row says its projects have the dependencies

### Scenario: a Go module that requires nothing

- **Given** a `go.mod` with no `require`
- **Then** the row reads `no dependencies`
