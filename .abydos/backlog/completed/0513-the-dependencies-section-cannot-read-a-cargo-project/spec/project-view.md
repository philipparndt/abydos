<!-- What this item changes about `project-view`. Folded into
     .abydos/backlog/spec/project-view.md by `abydos-backlog done`.

     Cargo is now read, so three requirements gain the cases that
     answer for it, and the Maven row's item number is corrected —
     the section says 0515 and the spec still said 0512.
-->

## MODIFIED Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one.

The list is read from what is already on disk. Nothing runs a build tool to
answer it.

What it lists is what came from outside. A dependency that is a directory
inside the project — a Cargo `path` dependency, the project's own crate — has a
row in the tree already, and listing it again under a heading that says it came
from elsewhere would show the same source twice.

### Scenario: a Swift package with its dependencies resolved

- **Given** a project with a `Package.resolved`
- **When** the project is opened
- **Then** the tree has a `Dependencies` row under the project's own files
- **And** it holds one row per package in `Package.resolved`

### Scenario: a Cargo project

- **Given** a project with a `Cargo.lock`
- **When** the `Dependencies` row is opened
- **Then** it holds one row per crate the lock file resolved

### Scenario: a crate that is a directory in the project

- **Given** a `Cargo.lock` naming a crate with no source — a `path` dependency
  or a workspace member
- **Then** that crate has no row in `Dependencies`

### Scenario: a directory with no build system in it

- **Given** a project with no manifest of any kind
- **When** the project is opened
- **Then** there is no `Dependencies` row

## MODIFIED Requirement: A dependency says which version it is and where it came from

Each package row carries the version the project resolved and an abbreviation
of its origin — the host and owner of a Swift package's repository, the module
path of a Go module, the registry a crate was published to. The whole origin,
the version and the directory the sources are in are on the row's tooltip,
which is where anything too long for the pane goes.

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

### Scenario: a package nobody has fetched

- **Given** a pin whose sources are in no checkout on this machine
- **Then** the package still has a row
- **And** the row cannot be opened

## MODIFIED Requirement: A kind of project this cannot read says so, on a row

The section covers every build system this program opens, whether or not it can
read that system's dependencies yet. A kind it cannot read shows a row saying
so, with the number of the backlog item that will teach it — never an empty
list, which would read as a project that depends on nothing.

A kind it *can* read, in a project that has resolved nothing yet, says that
instead, and says it in the words of the tool that would resolve it. A project
that has resolved nothing because something *above it* did the resolving says
where that was, rather than naming a command that would write nothing here.

### Scenario: a Maven project

- **Given** a project with a `pom.xml`
- **When** the `Dependencies` row is opened
- **Then** it holds one row reading `not read yet (0515)`

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

### Scenario: a Go module that requires nothing

- **Given** a `go.mod` with no `require`
- **Then** the row reads `no dependencies`
