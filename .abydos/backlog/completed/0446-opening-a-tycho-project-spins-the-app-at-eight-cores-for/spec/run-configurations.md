<!-- What this item changes about `run-configurations`. Folded into
     .abydos/backlog/spec/run-configurations.md by `abydos-backlog done`.

     ADDED, MODIFIED and REMOVED. A rename is a REMOVED and an ADDED.
     Write each requirement as it will read in the spec, in the present
     tense — not as a description of the edit.
     Nothing has been said about run-configurations yet, so this is all ADDED.
-->

## ADDED Requirement: What a project can run is found rather than configured

Opening a project lists what it can run without anybody writing a configuration
first: the targets of a Makefile, the modules of a Go repository, the goals of a
`pom.xml` or a `build.gradle`, the schemes of an Xcode project, Bazel targets,
Conan actions, the configurations IntelliJ and VS Code have already written, and
every Java or Kotlin class with a `main` method. Each one that names a file and
a line also puts a play button in the gutter beside it.

Build files are looked for three directories deep, because a repository commonly
keeps its module in a subdirectory with the deployment files beside it; entry
points are looked for through the whole tree, because a `main` method can be
anywhere.

### Scenario: a Maven module with one entry point

- **Given** a project with a `pom.xml` and a class declaring
  `public static void main(String[] args)`
- **When** the project is opened
- **Then** the list holds a Java configuration that runs that class, and the
  Maven goals of the module beside it

## ADDED Requirement: The list is refreshed by writes that could change it

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

Where the file system reports a burst too large to describe file by file, the
search is done, because a batch nobody can read the names of could be a checkout
that brought a whole module in. A search too many is slow; a search too few is a
play button that never appears.

At most one search runs at a time, with at most one more queued behind it: a
checkout across a large repository names thousands of source files in a handful
of batches, every one of them a real reason to look again, and each search but
the last would be stale before it finished.

### Scenario: a language server writing metadata beside the source

- **Given** a project of a thousand bundles, opened, with a Java language server
  importing it and writing `.project` and `.settings` into each one
- **When** those writes arrive as file system events
- **Then** no search of the project is made for any of them

### Scenario: a class written after the project was opened

- **Given** an open project whose list holds no Java entry point
- **When** a class declaring `public static void main(String[] args)` is written
  into it from outside the editor
- **Then** the list holds a configuration that runs that class

### Scenario: a checkout too large to describe file by file

- **Given** an open project
- **When** the file system reports that a directory changed without naming what
  changed inside it
- **Then** the project is searched again
