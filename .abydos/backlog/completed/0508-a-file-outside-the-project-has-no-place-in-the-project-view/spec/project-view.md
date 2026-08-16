<!-- What this item changes about `project-view`. Folded into
     .abydos/backlog/spec/project-view.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     Nothing has been said about project-view yet, so this is all ADDED.
-->

## ADDED Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one.

The list is read from what is already on disk. Nothing runs a build tool to
answer it.

### Scenario: a Swift package with its dependencies resolved

- **Given** a project with a `Package.resolved`
- **When** the project is opened
- **Then** the tree has a `Dependencies` row under the project's own files
- **And** it holds one row per package in `Package.resolved`

### Scenario: a directory with no build system in it

- **Given** a project with no manifest of any kind
- **When** the project is opened
- **Then** there is no `Dependencies` row

## ADDED Requirement: A dependency says which version it is and where it came from

Each package row carries the version the project resolved and an abbreviation
of its origin — the host and owner of a Swift package's repository, the module
path of a Go module. The whole origin, the version and the directory the
sources are in are on the row's tooltip, which is where anything too long for
the pane goes.

A package that has been resolved and never fetched is still a row. It has no
sources to open, which is a different thing from not being depended on.

### Scenario: a package resolved to a released version

- **Given** a `Package.resolved` pinning `Cadova` at `0.9.1` from
  `https://github.com/tomasf/Cadova.git`
- **When** the `Dependencies` row is opened
- **Then** the row reads `Cadova`, `0.9.1`, `github.com/tomasf`

### Scenario: a package pinned to a branch

- **Given** a pin with a branch and no version
- **Then** the row shows the branch

### Scenario: a package nobody has fetched

- **Given** a pin whose sources are in no checkout on this machine
- **Then** the package still has a row
- **And** the row cannot be opened

## ADDED Requirement: A kind of project this cannot read says so, on a row

The section covers every build system this program opens, whether or not it can
read that system's dependencies yet. A kind it cannot read shows a row saying
so, with the number of the backlog item that will teach it — never an empty
list, which would read as a project that depends on nothing.

A kind it *can* read, in a project that has resolved nothing yet, says that
instead, and says it in the words of the tool that would resolve it.

### Scenario: a Maven project

- **Given** a project with a `pom.xml`
- **When** the `Dependencies` row is opened
- **Then** it holds one row reading `not read yet (0512)`

### Scenario: a Swift package that has never been resolved

- **Given** a project with a `Package.swift` and no `Package.resolved`
- **Then** the row reads `no Package.resolved — run swift package resolve`

### Scenario: a Go module that requires nothing

- **Given** a `go.mod` with no `require`
- **Then** the row reads `no dependencies`

## ADDED Requirement: A dependency says which subproject resolved it

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

## ADDED Requirement: A file with no place in the tree is revealed in the section

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

## ADDED Requirement: `.build` is an ordinary folder

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
