## MODIFIED Requirement: A project shows what it depends on, beside its own files

The tree has two roots. The first is the project's directory. The second is
**Dependencies** — the packages the project depends on, named as packages
rather than as paths, in the place IntelliJ puts *External Libraries*. A
project whose directory holds no recognised build system has no second root at
all, rather than an empty one.

The list is read from what is already on disk. Nothing runs a build tool to
answer it. That holds even where the build tool is the obvious way to ask:
Conan's recipe is a Python program and evaluating it would be running somebody's
code to fill in a tree row, and `bazel query` starts a server that takes a lock
on the output base, which would leave this section and somebody's build waiting
on each other.

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

## MODIFIED Requirement: A kind of project this cannot read says so, on a row

The section covers every build system this program opens, whether or not it can
read that system's dependencies yet. A kind it cannot read shows a row saying
so, with the number of the backlog item that will teach it — never an empty
list, which would read as a project that depends on nothing.

A kind it *can* read, in a project that has resolved nothing yet, says that
instead, and says it in the words of the tool that would resolve it. A project
that has resolved nothing because something *above it* did the resolving says
where that was, rather than naming a command that would write nothing here.

Where no command would resolve it, the row says why instead of naming one. A
suggestion that cannot be followed is worse than none: the row's whole job is to
be believable about what is missing.

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

### Scenario: a Go module that requires nothing

- **Given** a `go.mod` with no `require`
- **Then** the row reads `no dependencies`
