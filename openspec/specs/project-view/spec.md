# Project view

## Purpose

The tree down the left of the window: what the project is made of, and what it
is made *from*. Its first root is the project's own directory, read lazily and
followed as it changes on disk. Its second is the dependencies — resolved
packages rather than paths — which is how a file belonging to no directory in
this project still has somewhere to be shown.
## Requirements
### Requirement: A project shows what it depends on, beside its own files

A project SHALL show what it depends on, beside its own files.

The tree has **up to three roots, and each is there only when it has something
in it.** The first is the project's directory. The second is **Dependencies** —
the packages the project depends on, named as packages rather than as paths, in
the place IntelliJ puts *External Libraries*. A project whose directory holds no
recognised build system has no second root at all, rather than an empty one —
until a symbol is followed out of it into a compiler's own sources, which is
something to show and so is shown. The third is **Claude Sessions**, which is
what a past agent session left behind for this project and has a requirement of
its own below.

**Each root claims a file in a fixed order** when one is revealed: the project's
own tree, then `Dependencies`, then `Claude Sessions`. The order never has to be
argued about, because nothing lives in two of them — a package's sources are not
under `/tmp`, and a session's scratch directory is not inside the project.

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

#### Scenario: a Swift package with its dependencies resolved

- **Given** a project with a `Package.resolved`
- **When** the project is opened
- **Then** the tree has a `Dependencies` row under the project's own files
- **And** it holds one row per package in `Package.resolved`

#### Scenario: a Cargo project

- **Given** a project with a `Cargo.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per crate the lock file resolved

#### Scenario: an npm project

- **Given** a project with a `package-lock.json`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per package the lock file resolved
- **And** a package installed twice at two versions, because two packages
  needed different ones, has a row for each

#### Scenario: a pnpm project

- **Given** a project with a `pnpm-lock.yaml`
- **When** the `Dependencies` row is opened
- **Then** the section is headed `pnpm` rather than `npm`
- **And** it holds one row per package the lock file's `packages` block
  resolved, each with the version on disk
- **And** a package named a second time under `snapshots`, once per set of
  peers it was built against, still has one row

#### Scenario: a yarn project

- **Given** a project with a `yarn.lock`, in either the yarn 1 syntax or the
  YAML one every yarn since 2 writes
- **When** the `Dependencies` row is opened
- **Then** the section is headed `yarn`
- **And** it holds one row per package the lock file resolved

#### Scenario: a project installed by two tools

- **Given** a project with both a `package-lock.json` and a `yarn.lock`
- **Then** the section is headed `npm`, and reads the same on every opening

#### Scenario: a Maven project

- **Given** a project with a `pom.xml` declaring three dependencies
- **When** the `Dependencies` row is opened
- **Then** it holds one row per dependency the POM declares

#### Scenario: a Gradle build with its dependencies locked

- **Given** a project with a `gradle.lockfile`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per coordinate the lock file resolved, transitive
  ones included

#### Scenario: a Gradle build with no lock file

- **Given** a build file whose `dependencies { }` block names two coordinates
- **Then** both have a row
- **And** a coordinate named inside `buildscript { }` has none, because that is
  the plugin classpath rather than what the project is built from

#### Scenario: a crate that is a directory in the project

- **Given** a `Cargo.lock` naming a crate with no source — a `path` dependency
  or a workspace member
- **Then** that crate has no row in `Dependencies`

#### Scenario: an npm workspace member

- **Given** a `package-lock.json` naming a member of the workspace, both by its
  path and as a link under `node_modules`
- **Then** that member has no row in `Dependencies`

#### Scenario: a yarn workspace member

- **Given** a `yarn.lock` whose entry resolves to `workspace:packages/app`
- **Then** that member has no row in `Dependencies`

#### Scenario: a Bazel workspace

- **Given** a project with a `MODULE.bazel.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per module the lock file selected
- **And** a module the lock merely *considered* — an older version whose
  `MODULE.bazel` was fetched to compare it and whose `source.json` was not — has
  no row, so one module never shows as three

#### Scenario: a Bazel workspace nobody has built

- **Given** a project with a `MODULE.bazel` and no lock file
- **When** the `Dependencies` row is opened
- **Then** it holds one row per `bazel_dep` the manifest declares

#### Scenario: a Conan project

- **Given** a project with a `conan.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per package the lock file resolved
- **And** the recipe is not executed to find them

#### Scenario: a directory with no build system in it

- **Given** a project with no manifest of any kind
- **When** the project is opened
- **Then** there is no `Dependencies` row

### Requirement: A dependency says which version it is and where it came from

A dependency SHALL say which version it is and where it came from.

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

#### Scenario: a package resolved to a released version

- **Given** a `Package.resolved` pinning `Cadova` at `0.9.1` from
  `https://github.com/tomasf/Cadova.git`
- **When** the `Dependencies` row is opened
- **Then** the row reads `Cadova`, `0.9.1`, `github.com/tomasf`

#### Scenario: a package pinned to a branch

- **Given** a pin with a branch and no version
- **Then** the row shows the branch

#### Scenario: a crate from crates.io

- **Given** a `Cargo.lock` resolving `serde` at `1.0.229` from the crates.io
  index
- **Then** the row reads `serde`, `1.0.229`, `crates.io`
- **And** it reads the same whether the lock file names the git index or the
  sparse one

#### Scenario: a crate from a git repository

- **Given** a `Cargo.lock` resolving `anyhow` from
  `git+https://github.com/dtolnay/anyhow#bf3ed914…`
- **Then** the row reads `github.com/dtolnay`
- **And** the tooltip has the whole source, revision included

#### Scenario: an npm package from the registry

- **Given** a `package-lock.json` resolving `lodash` at `4.17.21` from
  `https://registry.npmjs.org/lodash/-/lodash-4.17.21.tgz`
- **Then** the row reads `lodash`, `4.17.21`, `npmjs.com`
- **And** a package served from `registry.yarnpkg.com` reads the same, because
  it is the same registry
- **And** a package from any other registry reads that registry's host

#### Scenario: a yarn 1 package from the registry

- **Given** a `yarn.lock` whose `resolved` is a registry tarball with the
  file's own sha1 hung off the end of it as a fragment
- **Then** the row reads the registry, not the tarball URL

#### Scenario: a yarn package from the registry, in the newer syntax

- **Given** a `yarn.lock` entry resolving to `lodash@npm:4.17.21`
- **Then** the row reads `lodash`, `4.17.21`, `npmjs.com`

#### Scenario: an npm package from a git repository

- **Given** a `package-lock.json` resolving a package from
  `git+https://github.com/dtolnay/anyhow.git#bf3ed914`
- **Then** the row reads `github.com/dtolnay`, and not the host alone

#### Scenario: a package whose lock file records no origin

- **Given** an entry in a `package-lock.json` with no `resolved`, or a
  `pnpm-lock.yaml` package whose resolution is an integrity hash and nothing
  else
- **Then** the row shows the version and no origin

#### Scenario: a pnpm package the lock file does name a source for

- **Given** a `pnpm-lock.yaml` package whose resolution names a tarball on
  another registry
- **Then** the row reads that registry's host

#### Scenario: a Maven dependency whose jar has been downloaded

- **Given** a `pom.xml` naming `commons-lang3` at `3.14.0`, whose jar is in the
  local repository
- **Then** the row reads `commons-lang3`, `3.14.0`, `org.apache.commons`
- **And** the row cannot be opened
- **And** its tooltip names the jar rather than saying the dependency was not
  fetched

#### Scenario: a package under Plug'n'Play

- **Given** a yarn project with no `node_modules` and the package's zip in
  `.yarn/cache`
- **Then** the row cannot be opened, and its tooltip names the archive rather
  than saying the dependency was not fetched

#### Scenario: a version the project does not state

- **Given** a `pom.xml` dependency with no `<version>`, managed by a BOM that
  is not in the project
- **Then** the row has the name and the group and no version, rather than the
  `${…}` or the blank the file holds

#### Scenario: a package nobody has fetched

- **Given** a pin whose sources are in no checkout on this machine
- **Then** the package still has a row
- **And** the row cannot be opened

### Requirement: A kind of project this cannot read says so, on a row

A kind of project this cannot read SHALL say so, on a row.

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

#### Scenario: a Swift package that has never been resolved

- **Given** a project with a `Package.swift` and no `Package.resolved`
- **Then** the row reads `no Package.resolved — run swift package resolve`

#### Scenario: a Cargo project that has never been resolved

- **Given** a project with a `Cargo.toml` and no `Cargo.lock`
- **Then** the row reads `no Cargo.lock — run cargo fetch`

#### Scenario: an npm project that has never been installed

- **Given** a project with a `package.json` and no lock file of any kind
- **Then** the row reads `no package-lock.json — run npm install`

#### Scenario: a lock file this program cannot make sense of

- **Given** a `pnpm-lock.yaml` with no `lockfileVersion` in it
- **Then** the row says the file could not be read
- **And** it does not read as a project with no dependencies

#### Scenario: a crate that is a member of a workspace

- **Given** a crate with a `Cargo.toml`, no `Cargo.lock` of its own, and a
  workspace above it that has one
- **Then** the row says the crate is resolved in that workspace, and names it
- **And** the workspace's own list is not repeated under the member

#### Scenario: a member of an npm workspace

- **Given** a package with a `package.json`, no lock file of its own, and a
  directory above it whose `package.json` declares `workspaces` — or which has
  a `pnpm-workspace.yaml` beside it — and which has a lock file
- **Then** the row says the package is resolved in that workspace, and names it
- **And** the workspace's own list is not repeated under the member

#### Scenario: a Conan project that has never been resolved

- **Given** a project with a `conanfile.py` or a `conanfile.txt` and no
  `conan.lock`
- **Then** the row names the command that writes one, which is
  `conan lock create .` and not `conan install`

#### Scenario: a lock file from an older version of the tool

- **Given** a `conan.lock` written by Conan 1, which is valid JSON and says none
  of what Conan 2's says
- **Then** the row says so
- **And** it does not read as a project with no dependencies

#### Scenario: a Bazel workspace declared in Starlark

- **Given** a project with a `WORKSPACE` and no `MODULE.bazel`
- **Then** the row says its dependencies are Starlark and that nothing on disk
  lists them
- **And** it names no command, because none of them would produce such a file

#### Scenario: a note too long for the pane

- **Given** any row of this kind
- **When** it is cut off at the edge of the pane
- **Then** its tooltip has the whole sentence

#### Scenario: a Maven POM that only aggregates modules

- **Given** a `pom.xml` with `<packaging>pom</packaging>`, a list of modules and
  no dependencies of its own
- **Then** the row says its modules have the dependencies

#### Scenario: a Gradle settings file with no build file beside it

- **Given** a directory with a `settings.gradle` and no `build.gradle`
- **Then** the row says its projects have the dependencies

#### Scenario: a Go module that requires nothing

- **Given** a `go.mod` with no `require`
- **Then** the row reads `no dependencies`

### Requirement: A dependency says which subproject resolved it

A dependency SHALL say which subproject resolved it.

Dependencies are read for the whole project and for every subproject in it, not
only for the part in scope — two subprojects may resolve different versions of
the same package, and a row that did not say whose it was could not tell them
apart.

Where more than one root has dependencies, each gets a row of its own naming it
by its path relative to the project, with the kind of build system beside it.
Where only one has, the packages hang straight off `Dependencies` and the kind
is named on that row instead.

#### Scenario: a repository of eight subprojects

- **Given** a project holding `cadova-models`, `go-service` and
  `java/maven-service`
- **When** the `Dependencies` row is opened
- **Then** there is a row for each, named `cadova-models`, `go-service` and
  `java/maven-service`
- **And** each names its build system

#### Scenario: a project that is one package

- **Given** a project whose only dependencies are its own
- **Then** the packages are directly under `Dependencies`
- **And** `Dependencies` names the build system

### Requirement: A file with no place in the tree is revealed in the section

A file with no place in the tree SHALL be revealed in the section.

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

#### Scenario: following a symbol into a package

- **Given** a Swift file in the project that uses a type from a package
- **When** the definition of that type is asked for
- **Then** the file opens
- **And** the tree selects it under that package in `Dependencies`
- **And** the folder it is in shows the rest of the package's files beside it

#### Scenario: the same file, from the other checkout

- **Given** a file under the project's own `.build/checkouts`
- **When** it is opened
- **Then** it is revealed in `Dependencies` rather than under `.build`

#### Scenario: a file that belongs nowhere in this window

- **Given** a file open in a tab, from outside the project and from no package
  or toolchain
- **When** the tree is asked to reveal it
- **Then** it says the file is not in the tree, and why
- **And** switching to that tab says nothing

### Requirement: `.build` is an ordinary folder

`.build` SHALL be an ordinary folder.

A directory of fetched or built dependencies inside the project — `.build` for
a Swift package, `node_modules` for an npm project — is shown as what it is: a
folder, in the tree, marked as build output the way any excluded directory is.
It is not hidden because the section also shows part of it — it holds build
products as well as checkouts, and a tree that quietly omits a directory is one
nobody can trust. Nothing opens it on somebody's behalf, because a reveal that
would land inside it goes to the section instead.

#### Scenario: a project that has been built

- **Given** a project with a `.build` directory
- **When** the project is opened
- **Then** `.build` is a row in the tree, tinted as excluded output

#### Scenario: a file revealed inside a checkout

- **Given** the same project
- **When** a file inside `.build/checkouts` is opened
- **Then** `.build` stays folded

#### Scenario: a file revealed inside `node_modules`

- **Given** an npm project with its packages installed
- **When** a file inside `node_modules` is opened
- **Then** it is revealed on that package's row in the section, with the rest of
  the package's files beside it
- **And** `node_modules` stays folded

### Requirement: A list that is read and incomplete says what is missing

A list that is read and incomplete SHALL say what is missing.

Some build systems keep the resolved graph on disk and some keep only the
question. A `Package.resolved`, a `go.mod`, a `Cargo.lock` and a
`gradle.lockfile` are answers; a `pom.xml` and a `dependencies { }` block are
inputs to an answer, holding the direct dependencies and nothing transitive.

A list read from one of those is shown — the rows in it are true, and dropping
them would hide dependencies the project really has — with a note under the
packages saying what is not in it. The note names what is actually missing from
*this* project rather than a fixed sentence: the transitive dependencies
always, the versions this project leaves to something it cannot see, and a
parent it does not contain. A list with nothing missing gets no note, so a
Gradle build that has locked its dependencies reads exactly as a Cargo project
does.

A note is a whole sentence and the pane is narrow, so a note's tooltip leads
with its own message.

#### Scenario: a Maven project

- **Given** a `pom.xml` with three dependencies, one of whose versions a BOM
  outside the project manages
- **When** the `Dependencies` row is opened
- **Then** all three have a row
- **And** under them a note says the list is the direct dependencies only, and
  that Maven resolves the transitive ones and one of these versions

#### Scenario: a Gradle build that has locked its dependencies

- **Given** a project with a `gradle.lockfile`
- **Then** its packages have no note under them

#### Scenario: a note too long for the pane

- **Given** a note the sidebar cuts short
- **Then** the whole of it is on that row's tooltip

### Requirement: A folder a build system marks is a project of its own

A folder a build system marks SHALL be a project of its own.

A repository is often not one thing, so the folders inside it that a build
system has marked are projects in their own right: the tree stays whole,
because that is how somebody navigates, and one of them at a time can be the
part being worked on. Which folders those are is decided by the files in them —
`.git` and `.ideai`, `go.mod`, `Cargo.toml`, `package.json`, `build.zig`,
`pyproject.toml`, `CMakeLists.txt`, `Package.swift`, `pom.xml`, the Gradle
build files, `Chart.yaml`, a makefile under any of its three names, a Conan
recipe, and a Bazel workspace under any of the four names Bazel accepts. They
are looked for two directories deep, and nothing inside one of them is looked
at, because what is inside a module belongs to that module.

**One list decides five things at once**, which is what sets the bar a name has
to clear. A folder on it is offered in the menu the scope pill opens; it is
where the run configurations are read from and written to; it is the root a
language server is started on; it is the work tree git is asked about and the
directory a terminal opens in; and it is a root the **Dependencies** section
reads and gives a group row to. So a name that is right nine times out of ten
is not good enough — the tenth is an ordinary folder given a scope nobody asked
it to have, and that is a worse failure than the folder that should be a
project and is not.

Which is why a name has to *declare* a project rather than mention one. A Conan
recipe is the package: it names it, and it is what `conan create` builds, so a
folder holding one is a project with nothing else in it. A `conanfile.txt` only
says what a directory consumes — it is what sits in the `examples/` beside a
recipe — and a directory that is a project as well as a consumer has the build
file that says so and is found by that instead.

And the names are compared as names. A Mac formats a disk case-insensitively,
so asking the file system whether a `WORKSPACE` is present answers yes for any
folder with an ordinary `workspace/` directory in it; the names a folder holds
are read and matched exactly instead. A symbolic link is neither followed nor
counted, which is what keeps a built Bazel workspace from offering its own
execroot — reached through the `bazel-<workspace>` link beside `MODULE.bazel` —
as a project inside itself.

#### Scenario: a Bazel workspace inside a repository

- **Given** a repository holding `services/build-farm/MODULE.bazel`
- **When** the project is opened
- **Then** `services/build-farm` is one of the projects inside it, and the
  **Dependencies** section gives it a group row of its own

#### Scenario: a Conan recipe inside a repository

- **Given** a repository holding `native/fmt/conanfile.py`
- **Then** `native/fmt` is one of the projects inside it

#### Scenario: a folder that only lists what it consumes

- **Given** a `samples/` folder whose only build-system file is a
  `conanfile.txt`
- **Then** it is not a project of its own
- **And** a folder holding a `conanfile.txt` beside a `CMakeLists.txt` is one,
  by the `CMakeLists.txt`

#### Scenario: a folder called `workspace`

- **Given** a folder holding an ordinary directory called `workspace` and no
  build-system file
- **Then** it is not a Bazel workspace: it is not a project of its own, and it
  gets no Bazel row in the **Dependencies** section

### Requirement: A compiler's own sources have a row, once somebody goes there

A compiler's own sources SHALL have a row, once somebody goes there.

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

#### Scenario: following a symbol into the Go standard library

- **Given** a Go module whose `go.mod` requires nothing
- **When** a symbol is followed into the toolchain's own `src/time/time.go`
- **Then** `Dependencies` still reads `no dependencies` for that module, which
  is the truth about its `go.mod`
- **And** beside it there is a `Go standard library` row reading
  `go1.26.6  ·  toolchain`
- **And** the file is selected under it, with the rest of `time` beside it

#### Scenario: a system header

- **Given** a file opened from inside an SDK — `MacOSX.sdk/usr/include/stdio.h`
- **Then** the section has a `macOS SDK` row reading `27.0  ·  SDK`
- **And** the header is revealed under it

#### Scenario: a toolchain nobody has been into

- **Given** a project just opened, whatever is installed on the machine
- **Then** there is no toolchain row

#### Scenario: opening the row

- **Given** a `Go standard library` row
- **When** it is opened
- **Then** its children are the standard library's packages — `time`, `fmt`,
  `net` — rather than the distribution's `api`, `bin`, `pkg` and `test`
- **And** nothing under it was read before it was opened

#### Scenario: a directory that merely looks like one

- **Given** a project holding a `src` directory, and a `VERSION` file beside it
  that is not a Go version
- **Then** it is not a toolchain, and gets no row

### Requirement: What a past session left behind has a root of its own

The project view SHALL show, as a root of its own, the Claude Code sessions of
this project: what past ones left behind, and any that is running now.

Every session gets a scratch directory of its own, keyed by the project's path:
reproductions, driven-run logs, screenshots of a fault, a throwaway checkout
somebody was told not to drive against a real one. They are useful for weeks and
reachable only by knowing the shape of the path and a session's UUID.

**A session SHALL have a row when it left files, or when it is active now.**
Keying on files alone hides the session somebody is sitting in: Claude Code makes
the scratch directory when a session starts and writes into it only when a tool
needs a temporary file, so a session that has been asked one question has an
empty directory — seven of the eleven session directories on this machine hold
nothing at all. Keying on the transcript instead SHALL NOT be done: this project
has fourteen transcripts and two scratch directories, and the twelve whose files
went with a reboot would be rows leading nowhere.

**A root rather than a shelf inside `Dependencies`.** What a session left behind
is not something the project depends on, and the heading would be a stretch.
The argument that was made *against* a third root — that it would have to exist
before anything had been found to put in it, which is a permanent empty row on
every project — does not apply: whether a session has left anything is knowable
before anybody asks, because the directory either exists or it does not. So this
root SHALL follow the rule `Dependencies` follows, and be absent when it is
empty.

It SHALL be named for the tool whose files these are. The two shorter names are
taken by other features of this app: "Scratch" is the pane for files somebody
writes on purpose, and "Sessions" is the editor's tabs and splits coming back.

**Nothing SHALL be written, and nothing run.** These are another program's
directories, read the way a lock file is read.

The sessions SHALL be those of the project the window is showing. A worktree is
a project of its own with sessions of its own, and a session started in a
subdirectory is filed under a key of its own and is not this project's.

#### Scenario: a project agents have worked on

- **GIVEN** a project with scratch directories from four past sessions
- **WHEN** the project is opened
- **THEN** the tree has a `Claude Sessions` root under `Dependencies`
- **AND** it holds one row per session, most recent first

#### Scenario: a project nobody has worked on

- **GIVEN** a project with no session directories and nothing running
- **WHEN** the project is opened
- **THEN** there is no `Claude Sessions` root, rather than an empty one

#### Scenario: another project's sessions

- **GIVEN** two projects, each with sessions of its own
- **WHEN** each is opened
- **THEN** each shows only its own

#### Scenario: a session whose files went with a reboot

- **GIVEN** a session whose transcript is still on disk and whose scratch
  directory is not, and which is not running
- **WHEN** the tree is read
- **THEN** that session has no row, rather than a row leading nowhere

### Requirement: A session's row says which session it was

A session's row SHALL say which session it was, in terms somebody recognises.

A UUID identifies nothing to a person. What makes a session recognisable is what
it was *for*, when it last did anything, and how much it left — so the row SHALL
carry the first thing that was asked of that session, when it last wrote, and how
much is in it.

**The first message SHALL be read from the head of the transcript**, never by
reading the file: a single day's session in this repository produced a
twenty-megabyte transcript, and there are eighteen of them for this project
alone. A transcript that cannot be read leaves the row named by its time and
size, which is still more than an id.

**A transcript SHALL NOT be offered as a file to open.** Twenty megabytes of
JSONL in an editor is not reading a conversation. Its path SHALL be available on
the row, for pointing another tool at it.

#### Scenario: a session with a transcript beside it

- **GIVEN** a session whose transcript begins with a request to fix a crash
- **WHEN** its row is drawn
- **THEN** the row says something of that request, when it last wrote, and how
  much it holds

#### Scenario: a transcript that cannot be read

- **GIVEN** a session whose transcript is missing or unreadable
- **WHEN** its row is drawn
- **THEN** the row is named by its time and size, and says nothing it cannot
  support

### Requirement: A session's row is a directory row

A session's row SHALL behave as any directory row in the tree does.

Its children are the files that session left — its scratchpad, and the output of
any subagents it ran. They SHALL list lazily, open, and be walked with the arrow
keys, exactly as a package's files under `Dependencies` do; **there SHALL NOT be
a second kind of file row.**

A file opened from inside one SHALL be revealed there, with the root and the
folders above it opened and the file selected — the same reveal a package's file
gets.

**But the root and a session's row are not files, and SHALL NOT be offered a
file's menu.** Reported twice: right-clicking a session row offered New, Rename,
Open Externally and *Move to Trash* — which reads as an offer to delete somebody's
session — and after that was fixed for session rows, the root still offered all of
it, which is the row anybody tries first. Each of those two rows SHALL offer only
what applies to it: the directory it stands for, and for a session, the command
that carries that session on.

#### Scenario: opening something a session left

- **GIVEN** a session row holding a screenshot and a log
- **WHEN** the row is opened and the log is chosen
- **THEN** the log opens in an editor tab like any other file

#### Scenario: revealing a file from a scratch directory

- **GIVEN** a file open in a tab from a session's scratch directory
- **WHEN** the tree is asked to reveal it
- **THEN** it is selected under that session's row

### Requirement: A session that is running has a row before it has written anything

A session running in this project SHALL have a row, whether or not it has written
a file.

This is the case that was reported: a terminal opened in an empty project,
`claude` started in it, and nothing under `Claude Sessions` — because the row was
keyed on a scratch directory that was empty and stayed empty, while the session's
transcript was three hundred kilobytes and growing.

**Where liveness is read from SHALL be the hook while the app is running.**
Claude Code runs a hook on every event and it already posts `event`, `session`
and `cwd` to every listening process; `SessionStart` and `SessionEnd` bracket a
session exactly, so nothing has to be inferred and no directory has to be
watched. A hook event belongs to this project when the slug of its `cwd` is one
of this project's slugs — the same key the scratch directories are filed under.

**Where there was no hook event to hear, liveness MAY be read from when the
session's transcript was last written**, which is the one file written the moment
a session starts and again every few seconds while it runs. This is a proxy and
the row SHALL NOT overstate it: a session the hook has spoken for is *running*,
and a session known only by a recent transcript is *active* and says when it last
wrote.

**A row SHALL NOT claim a size it has not measured.** A session with nothing
under it yet says that it is running, never "0 files", and SHALL NOT be given a
disclosure triangle until there is something behind it.

#### Scenario: a session started in an empty project

- **GIVEN** a project with no session files at all
- **WHEN** a Claude Code session is started in it
- **THEN** the `Claude Sessions` root appears with a row for that session
- **AND** the row says what was asked of it and that it is running, and offers
  nothing to expand

#### Scenario: a live session that starts writing

- **GIVEN** a row for a running session with nothing under it
- **WHEN** that session writes a file into its scratchpad
- **THEN** the row gains what it holds and becomes expandable
- **AND** whatever was expanded and selected in the tree is still expanded and
  selected

#### Scenario: a session running before the window opened

- **GIVEN** a session running in this project, started before the project was
  opened, that has written no files
- **WHEN** the project is opened
- **THEN** it has a row, named by what was asked of it and when it last wrote

#### Scenario: a session that ended without writing anything

- **GIVEN** a row for a running session that has written no files
- **WHEN** that session ends
- **THEN** its row goes, because there is nothing left for it to lead to

### Requirement: The root is read again without the project being reopened

The `Claude Sessions` root SHALL be read again while the project stays open.

It is read once today, when the project is loaded, so a session that starts,
works and ends while somebody watches changes nothing on screen and there is no
gesture short of closing the project that would.

It SHALL be re-read on the events that can change which sessions have a row —
a session starting, a session ending, a turn finishing — and when the window
comes forward, which catches a session that started while the app was asleep or
whose hooks are not installed.

**It SHALL NOT be re-read on every hook event.** A session at work sends one on
every tool use, dozens a minute, and counting what is under a session means
walking it. **`/tmp/claude-<uid>` SHALL NOT be watched**, for the reason already
recorded: every agent on the machine writes there several times a second, and a
watcher would rebuild a root nobody is looking at for somebody else's session.

**A redraw SHALL happen only when the answer changed.** Rebuilding the root
throws away every row's identity and collapses what somebody had open while they
were reading it, and a session that is merely still running has not changed
anything.

#### Scenario: a session started while the project is open

- **GIVEN** an open project showing no `Claude Sessions` root
- **WHEN** a session is started in that project
- **THEN** the root appears without the project being reopened

#### Scenario: a session at work

- **GIVEN** an open project with a running session using tools
- **WHEN** its hook fires on every tool use
- **THEN** the root is not rebuilt for events that change no row

#### Scenario: a session started while the app was asleep

- **GIVEN** a session started in this project while the window was not in front
- **WHEN** the window comes forward
- **THEN** the root has been read again and the session has a row

### Requirement: A driven run reads the root without liveness

A driven run SHALL read the `Claude Sessions` root from files alone, and SHALL
NOT show a session as running or active.

This is the answer already given for the toast corner, asked again about the
tree. A screenshot is pinned to a fixed window size, a fixed panel height and a
fresh copy of the project, because anything that varies per machine is a picture
that looks different for everybody who takes it — and a Claude session running in
somebody else's terminal is exactly that. A tree is pointed at by `--screenshot`
far more often than the corner is.

Both sources of news from outside the run SHALL be declined, not only the hook:
a run that ignores the notification but still reads transcript times has moved
the problem rather than answered it.

**But a way to look at the row SHALL remain**, which is the other half of what
0451 decided. "No toasts on a capture run" was rejected there because
`--toast --screenshot` is the only way to look at a toast, and a corner
photographed empty looks exactly like a corner with nothing to say — a tree
photographed without a live row looks exactly like a tree that cannot draw one.
So a driven run SHALL be able to say that a session is running in the project it
opened, and to say it either at the moment the project opens or after a delay,
because those are two different claims: one is the read on the open path and the
other is the redraw, and the redraw can be driven no other way.

#### Scenario: a capture taken while somebody is working

- **GIVEN** a session running in the project being captured, which the run did
  not name
- **WHEN** a driven run reads the tree
- **THEN** the root shows only what sessions left behind, and no row says
  anything is running

#### Scenario: a picture of a live row

- **GIVEN** a driven run told that a session is running in the project it opens
- **WHEN** the tree is read
- **THEN** that session has a row saying it is running, and the picture is the
  same on every machine
