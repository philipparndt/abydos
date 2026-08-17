# Project view

The tree down the left of the window: what the project is made of, and what it
is made *from*. Its first root is the project's own directory, read lazily and
followed as it changes on disk. Its second is the dependencies — resolved
packages rather than paths — which is how a file belonging to no directory in
this project still has somewhere to be shown.

## Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one.

The list is read from what is already on disk. Nothing runs a build tool to
answer it — not `swift package dump-package`, not `cargo metadata`, not `mvn
dependency:list`, and not Gradle, which was expected to be the kind that forced
the rule and turned out to be the kind that needs it least.

What it lists is what came from outside. A dependency that is a directory
inside the project — a Cargo `path` dependency, a Gradle `project(":common")`,
the project's own crate — has a row in the tree already, and listing it again
under a heading that says it came from elsewhere would show the same source
twice.

### Scenario: a Swift package with its dependencies resolved

- **Given** a project with a `Package.resolved`
- **When** the project is opened
- **Then** the tree has a `Dependencies` row under the project's own files
- **And** it holds one row per package in `Package.resolved`

### Scenario: a Cargo project

- **Given** a project with a `Cargo.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per crate the lock file resolved

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

### Scenario: a directory with no build system in it

- **Given** a project with no manifest of any kind
- **When** the project is opened
- **Then** there is no `Dependencies` row

## Requirement: A dependency says which version it is and where it came from

Each package row carries the version the project resolved and an abbreviation
of its origin — the host and owner of a Swift package's repository, the module
path of a Go module, the registry a crate was published to, the group a Maven
or Gradle coordinate names. The whole origin, the version and the directory the
sources are in are on the row's tooltip, which is where anything too long for
the pane goes.

A package that has been resolved and never fetched is still a row. It has no
sources to open, which is a different thing from not being depended on.

A dependency that resolves to a **file** rather than to sources is a row with
nothing under it, and its tooltip names the file. The JVM is where this
happens: Maven and Gradle fetch a jar, and a row pointed at the directory that
jar sits in would open onto a jar and a checksum rather than onto a package. It
is a different state from never having been fetched, and the tooltip says which
of the two it is.

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

### Scenario: a Maven dependency whose jar has been downloaded

- **Given** a `pom.xml` naming `commons-lang3` at `3.14.0`, whose jar is in the
  local repository
- **Then** the row reads `commons-lang3`, `3.14.0`, `org.apache.commons`
- **And** the row cannot be opened
- **And** its tooltip names the jar rather than saying the dependency was not
  fetched

### Scenario: a version the project does not state

- **Given** a `pom.xml` dependency with no `<version>`, managed by a BOM that
  is not in the project
- **Then** the row has the name and the group and no version, rather than the
  `${…}` or the blank the file holds

### Scenario: a package nobody has fetched

- **Given** a pin whose sources are in no checkout on this machine
- **Then** the package still has a row
- **And** the row cannot be opened

## Requirement: A kind of project this cannot read says so, on a row

The section covers every build system this program opens, whether or not it can
read that system's dependencies yet. A kind it cannot read shows a row saying
so, with the number of the backlog item that will teach it — never an empty
list, which would read as a project that depends on nothing.

A kind it *can* read, in a project that has resolved nothing yet, says that
instead, and says it in the words of the tool that would resolve it. A project
that has resolved nothing because something *above it* did the resolving says
where that was, rather than naming a command that would write nothing here; and
a project whose own job is to hold other projects says that its modules are
where the dependencies are.

### Scenario: a Bazel project

- **Given** a project with a `MODULE.bazel`
- **When** the `Dependencies` row is opened
- **Then** it holds one row reading `not read yet (0516)`

### Scenario: a Swift package that has never been resolved

- **Given** a project with a `Package.swift` and no `Package.resolved`
- **Then** the row reads `no Package.resolved — run swift package resolve`

### Scenario: a Cargo project that has never been resolved

- **Given** a project with a `Cargo.toml` and no `Cargo.lock`
- **Then** the row reads `no Cargo.lock — run cargo fetch`

### Scenario: a crate that is a member of a workspace

- **Given** a crate with a `Cargo.toml`, no `Cargo.lock` of its own, and a
  workspace above it that has one
- **Then** the row says the crate is resolved in that workspace, and names it
- **And** the workspace's own list is not repeated under the member

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

## Requirement: A dependency says which subproject resolved it

Dependencies are read for the whole project and for every subproject in it, not
only for the part in scope — two subprojects may resolve different versions of
the same package, and a row that did not say whose it was could not tell them
apart.

Where more than one root has dependencies, each gets a row of its own naming it
by its path relative to the project, with the kind of build system beside it.
Where only one has, the packages hang straight off `Dependencies` and the kind
is named on that row instead.

### Scenario: a repository of eight subprojects

- **Given** a project holding `cadova-models`, `go-service` and
  `java/maven-service`
- **When** the `Dependencies` row is opened
- **Then** there is a row for each, named `cadova-models`, `go-service` and
  `java/maven-service`
- **And** each names its build system

### Scenario: a project that is one package

- **Given** a project whose only dependencies are its own
- **Then** the packages are directly under `Dependencies`
- **And** `Dependencies` names the build system

## Requirement: A file with no place in the tree is revealed in the section

A package row is a directory, so the rows beneath it are the package's own
files and everything the tree does with a file it does with them: they list
lazily, they open, and the arrow keys walk them.

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

## Requirement: `.build` is an ordinary folder

A checkout directory inside the project is shown as what it is: a folder, in
the tree, marked as build output the way any excluded directory is. It is not
hidden because the section also shows part of it — it holds build products as
well as checkouts, and a tree that quietly omits a directory is one nobody can
trust. Nothing opens it on somebody's behalf, because a reveal that would land
inside it goes to the section instead.

### Scenario: a project that has been built

- **Given** a project with a `.build` directory
- **When** the project is opened
- **Then** `.build` is a row in the tree, tinted as excluded output

### Scenario: a file revealed inside a checkout

- **Given** the same project
- **When** a file inside `.build/checkouts` is opened
- **Then** `.build` stays folded

## Requirement: A list that is read and incomplete says what is missing

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

### Scenario: a Maven project

- **Given** a `pom.xml` with three dependencies, one of whose versions a BOM
  outside the project manages
- **When** the `Dependencies` row is opened
- **Then** all three have a row
- **And** under them a note says the list is the direct dependencies only, and
  that Maven resolves the transitive ones and one of these versions

### Scenario: a Gradle build that has locked its dependencies

- **Given** a project with a `gradle.lockfile`
- **Then** its packages have no note under them

### Scenario: a note too long for the pane

- **Given** a note the sidebar cuts short
- **Then** the whole of it is on that row's tooltip
