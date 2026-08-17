# Run configurations

## Purpose

What the play button offers. A project is read for the things it can already do
— build files, entry points, the configurations other editors have written — so
that running something is not gated on first describing how. This page is about
what is looked for, when it is looked for again, and what looking again costs on
a project of a thousand modules.

## Requirements

### Requirement: What a project can run is found rather than configured

What a project can run SHALL be found rather than configured.

Opening a project lists what it can run without anybody writing a configuration
first: the targets of a Makefile, the modules of a Go repository, the goals of a
`pom.xml` or a `build.gradle`, the schemes of an Xcode project, the executables
and tests of a Swift package, Bazel targets, Conan actions, the configurations
IntelliJ and VS Code have already written, and every Java or Kotlin class with a
`main` method. Each one that names a file and a line also puts a play button in
the gutter beside it.

Build files are looked for three directories deep, because a repository commonly
keeps its module in a subdirectory with the deployment files beside it; entry
points are looked for through the whole tree, because a `main` method can be
anywhere.

#### Scenario: a Maven module with one entry point

- **Given** a project with a `pom.xml` and a class declaring
  `public static void main(String[] args)`
- **When** the project is opened
- **Then** the list holds a Java configuration that runs that class, and the
  Maven goals of the module beside it

### Requirement: The list is refreshed by writes that could change it

The list SHALL be refreshed by writes that could change it.

The list is found again when a file is written that could define a
configuration — a source file that might hold a `main` method, a build file, an
Xcode project, or anything under `.idea` or `.vscode` — so a class written after
the project was opened gets its play button without the project being reopened.

Writes that cannot define one do not cause the search. This is not an
optimisation of a search that would otherwise merely be slow: the search reads
every Java and Kotlin source in the project, and a language server importing a
Maven or Tycho reactor writes `.project`, `.classpath` and `.settings` into
every module it touches. Doing the search once per such write cost **668 seconds
of processor time in the ninety after opening** a thousand-bundle Eclipse
product — eight to nine cores, for as long as anything was writing — against
eleven seconds for the same open once the writes that cannot matter are ignored.

What counts is a name and not an extension wherever it can be. `Package.swift`
is a build file and is watched for by that name; every other `.swift` in the
project is a source file that cannot define a configuration, and watching the
extension instead would put every save in every Swift project through the whole
search.

Where the file system reports a burst too large to describe file by file, the
search is done, because a batch nobody can read the names of could be a checkout
that brought a whole module in. A search too many is slow; a search too few is a
play button that never appears.

At most one search runs at a time, with at most one more queued behind it: a
checkout across a large repository names thousands of source files in a handful
of batches, every one of them a real reason to look again, and each search but
the last would be stale before it finished.

#### Scenario: a language server writing metadata beside the source

- **Given** a project of a thousand bundles, opened, with a Java language server
  importing it and writing `.project` and `.settings` into each one
- **When** those writes arrive as file system events
- **Then** no search of the project is made for any of them

#### Scenario: a class written after the project was opened

- **Given** an open project whose list holds no Java entry point
- **When** a class declaring `public static void main(String[] args)` is written
  into it from outside the editor
- **Then** the list holds a configuration that runs that class

#### Scenario: a manifest written beside a Swift source

- **Given** an open Swift project
- **When** an ordinary `.swift` source file is saved
- **Then** no search is made; and when a `Package.swift` is written, one is

#### Scenario: a checkout too large to describe file by file

- **Given** an open project
- **When** the file system reports that a directory changed without naming what
  changed inside it
- **Then** the project is searched again

### Requirement: A Swift package offers its executables and its tests

A Swift package SHALL offer its executables and its tests.

A directory holding a `Package.swift` offers one entry for each of the package's
executable products, and one `swift test` when the package declares a test
target. All of them run in the **package root** — the directory the manifest is
in, which is both where `swift` has to be invoked to find the package and where
a run writes whatever it writes. A package with only libraries in it offers
nothing, and one with no test target is not offered a `swift test` that would
find nothing to run.

The name offered is the executable *product's*, which is not always the target's:
a package declaring `.executable(name: "abydos-hook", targets: ["AbydosHook"])`
offers `abydos-hook`, because handed the target's name SwiftPM answers "no
executable product named 'AbydosHook'". An executable target that no product
claims has an implicit product of its own name, and is offered under it.

`swift test` is offered and never saved, which is the rule about test runs
everywhere else in this list.

#### Scenario: a package with two executables and one of them renamed

- **Given** a package whose manifest declares an executable product
  `alpha-tool` for a target `AlphaTarget`, a second executable target `beta`
  that no product claims, and a test target
- **When** the project is opened
- **Then** the list holds `swift run alpha-tool`, `swift run beta` and
  `swift test`, and not `swift run AlphaTarget`

#### Scenario: the model a run writes

- **Given** a package in `tools/` whose executable writes a file beside itself
- **When** that executable is run from the list
- **Then** it runs with `tools/` as its working directory, and the file it
  writes is in `tools/`

### Requirement: A manifest is read and not run

A manifest SHALL be read and SHALL NOT be run.

What a Swift package holds is read out of the text of `Package.swift`. It is not
asked of `swift package dump-package`, which is the same choice made about
`xcodebuild -list` for a scheme and `bazel query` for a target, and for one
reason more than either of those had: a manifest is a program, and asking means
compiling and running somebody's build script to fill in a menu — which is
already refused for `conanfile.py`.

Three costs were measured rather than assumed. Asking takes **0.74 to 0.92
seconds per manifest**, warm cache or cold, on a search that runs once per
directory three deep and again on every write that could change the answer. It
**writes a `.build` directory into the project** as a side effect of being asked,
so merely looking at what a project can run would leave build output in it. And
it answers with whichever `swift` is first on the PATH, which one release behind
the manifest replies "package is using Swift tools version 6.3.0 but the
installed version is 6.1.2" and lists nothing at all — an empty run list because
somebody installed a version manager.

What reading the text cannot see is an executable whose name is not a string
literal, in a manifest that computes its targets. That is an entry missing rather
than an entry that does not run, which is the right way round.

#### Scenario: a package whose dependencies have never been fetched

- **Given** a package depending on something from the network, with no
  `Package.resolved` and no `.build` directory
- **When** the project is opened
- **Then** its executables are listed, and nothing is fetched, built or written
  into the package

#### Scenario: a target that has been commented out

- **Given** a manifest with one executable target, and a second on a line
  beginning `//`
- **When** the project is opened
- **Then** only the first is offered
