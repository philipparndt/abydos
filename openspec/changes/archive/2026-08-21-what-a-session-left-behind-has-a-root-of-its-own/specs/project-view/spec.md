## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: What a past session left behind has a root of its own

The project view SHALL show, as a root of its own, what past Claude Code
sessions left behind for this project.

Every session gets a scratch directory of its own, keyed by the project's path:
reproductions, driven-run logs, screenshots of a fault, a throwaway checkout
somebody was told not to drive against a real one. They are useful for weeks and
reachable only by knowing the shape of the path and a session's UUID.

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
a project of its own with sessions of its own.

#### Scenario: a project agents have worked on

- **GIVEN** a project with scratch directories from four past sessions
- **WHEN** the project is opened
- **THEN** the tree has a `Claude Sessions` root under `Dependencies`
- **AND** it holds one row per session, most recent first

#### Scenario: a project nobody has worked on

- **GIVEN** a project with no session directories
- **WHEN** the project is opened
- **THEN** there is no `Claude Sessions` root, rather than an empty one

#### Scenario: another project's sessions

- **GIVEN** two projects, each with sessions of its own
- **WHEN** each is opened
- **THEN** each shows only its own

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

#### Scenario: opening something a session left

- **GIVEN** a session row holding a screenshot and a log
- **WHEN** the row is opened and the log is chosen
- **THEN** the log opens in an editor tab like any other file

#### Scenario: revealing a file from a scratch directory

- **GIVEN** a file open in a tab from a session's scratch directory
- **WHEN** the tree is asked to reveal it
- **THEN** it is selected under that session's row

#### Scenario: files that went with a reboot

- **GIVEN** a session whose scratch directory no longer exists
- **WHEN** the tree is read
- **THEN** that session has no row, rather than a row leading nowhere
