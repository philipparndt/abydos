# 515. The dependencies section cannot read Maven or Gradle

Item 508 gave the project view a **Dependencies** section: the packages a
project depends on, named rather than pathed, each with where it came from and
its sources on disk so a file opened by following a symbol can be revealed
beside its siblings.

508 taught it Swift packages and Go modules and left the rest saying so out
loud. A `pom.xml` project's row in the section reads

    Maven — not read yet (0512)

and a Gradle build's says the same. This item is both of them, because they are
one question rather than two.

## Why one item and not two

Every other kind resolves to *sources on disk*: a Swift checkout under
`.build/checkouts`, a Go module in the module cache, a crate in the registry
cache. The JVM does not. `~/.m2/repository` and `~/.gradle/caches/modules-2`
hold **jars**, and a jar is not something the tree can browse the siblings of.
Sources are a separate artefact (`-sources.jar`) that is only there if somebody
asked for it, and the answer for both tools is the same answer, made once:

- list the coordinates and where they came from, and let a package row have no
  sources — the section already tolerates a package whose `localPath` is nil;
- or unpack `-sources.jar` somewhere and browse that, which is a cache of our
  own and a decision far larger than this section;
- or teach the tree to browse inside an archive, which is a feature in its own
  right and would serve every jar in the project, not only dependencies.

Whichever is chosen has to be chosen for Maven and for Gradle together, and
that is what makes them one item.

## What each takes

- **Maven.** `pom.xml` is XML and `<dependencies>` is right there, but the
  useful list is the *resolved* one: parents, `dependencyManagement`,
  properties and transitives all move it. `mvn dependency:list` answers
  properly and costs seconds and a JVM. `RunConfigurationDiscovery` already
  reads `pom.xml` as text for its goals; whether that is enough here is the
  first thing to find out.
- **Gradle.** There is no file to read. `build.gradle` is a program,
  `gradle dependencies` needs the daemon, and the whole reason `SwiftPackage`,
  `XcodeProject`, `BazelBuild` and `ConanProject` all read text rather than run
  the tool is that running the tool is slow, needs the right version on the
  PATH, and has side effects. Gradle is the case where that rule is hardest to
  keep and the case that decides whether the rule bends.

## Where the work goes

`Sources/AbydosKit/Project/ExternalDependencies.swift` — `case maven` and
`case gradle` in `DependencyKind`, and a reader for each. The section, the
reveal and the sibling browsing are already built and kind-agnostic; what is
not built is a package row that names a jar rather than a directory.

`abydos-examples/java` has both a `maven-service` and a `gradle-service` to
work against.

## What was read before anybody started, and not verified

An agent read the ground and stood down without writing code. None of this has
been near a compiler; treat it as a map, not as findings.

**Neither resolves whole from disk, and the two are not symmetric.**

*Maven has no lock file at all* — nothing in the checkout or in `target/` holds
the resolved graph. `pom.xml` is the **input** to resolution: transitives are
absent; a version may be `${jackson.version}`, resolvable only by merging
`<properties>` up the parent chain, and only the parents inside the checkout —
note `<relativePath/>` written empty explicitly means "not beside me", so a
reader that conflates absent with empty climbs out of the project into whatever
pom sits one directory up; and a dependency with no `<version>` is managed by
`<dependencyManagement>`, commonly an imported BOM living in `~/.m2` rather
than in the project. So the best a no-subprocess reader can do is **direct
dependencies, some of them version-less** — a real list that is also
incomplete. `MavenProject` already parses the POM with `XMLDocument` and keeps
`dependencies` as bare artifactIds.

*Gradle is the better case, not the worse one.* `gradle.lockfile` (Gradle 6+,
opt-in via `dependencyLocking`) **is** the resolved graph including transitives,
one `group:name:version=conf` per line; when it is there no caveat is needed at
all. The Gradle 5 form is `gradle/dependency-locks/*.lockfile`. Without it,
`dependencies { }` is text: `implementation 'g:a:v'`, the parenthesised form,
the `group:/name:/version:` map form, `platform(...)`, and `project(':common')`
which is internal and should be dropped the way 0513 drops a Cargo `path`
dependency. Two traps named: `dependencies { }` also appears inside
`buildscript { }` — the plugin classpath, not the project's — so the block must
be recognised at brace depth 0; and `"g:a:$version"` interpolates, so the
version is unknowable and should read as absent rather than as the literal.
`gradle/libs.versions.toml` is worth reading, since without it a modern build
yields no rows at all; alias matching needs `.`/`_`/`-` normalised on both
sides, and the `libs` accessor name is configurable in `settings.gradle`.

**This needs a state none of the three read kinds has.** `.unresolved` cannot
carry "the list is real and also incomplete". A caveat alongside `.packages`,
drawn as a note row under the package rows the way `DependencyTree` already
synthesises "no dependencies", is the shape suggested.

**The jar problem, and a tooltip that lies about it.** Both caches hold jars —
`~/.m2/repository/<group as dirs>/<artifact>/<version>/` and
`~/.gradle/caches/modules-2/files-2.1/<group>/<name>/<version>/<sha1>/` — so
`localPath` must stay nil, because a package row *is* a directory and pointing
it at the containing directory draws a package whose files are a jar and a pom.
But `DependencyNode.detail` renders `localPath?.path ?? "not fetched"`, and
"not fetched" is false about a dependency whose jar is sitting right there. A
second field for the artefact would let the tooltip name the jar while the row
stays unexpandable.

**Maven's local repository is computable; Gradle's is not.** `~/.m2/repository`,
overridden by `<localRepository>` in `~/.m2/settings.xml` (which may contain
`${user.home}`), and with no env var — so injection is the only way to test it.
Gradle's has a sha1 directory between the version and the jar, which is 0513's
lesson exactly: list and match, do not build the path and hope.
`GRADLE_USER_HOME` is the override there.

**One test moves.** `ExternalDependenciesTests.aKindNobodyHasTaughtSaysSoRatherThanShowingNothing`
uses `.maven` as its example of an unread kind, so it has to take another kind
when Maven starts being read.

## What was decided, and why

### The row names the jar, and cannot be opened

The first of the three answers the item offered: **list the coordinates and let
a package row have no sources.** `localPath` stays nil for every Maven and
Gradle dependency, so the row does not expand and the tree never draws a
"package" whose files are a jar and a checksum.

Unpacking `-sources.jar` was not done: it is a cache of our own, in a section
that has never written anything to disk. Browsing inside an archive was not
done either: it is a feature that would serve every jar in a project rather
than only these rows, and it is not this item's to invent.

What *was* built is the second field the pre-read asked for.
`ExternalDependency` now has an `artefact: URL?` — the one file a dependency
resolved to, when it resolved to a file rather than to sources — and
`DependencyNode.detail` renders `localPath ?? artefact ?? "not fetched"`. The
tooltip over `commons-lang3` now reads

    org.apache.commons
    version 3.14.0
    ~/.m2/repository/org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar

where it would otherwise have said `not fetched` over a jar sitting right
there.

### A fourth reading: real, and also incomplete

`.unresolved` cannot carry it and `.packages` claims the opposite, so
`DependencySet.Contents` has a fourth case:

    case partial([ExternalDependency], caveat: String)

drawn as the package rows *and* one note under them, in the same shape as the
`no dependencies` note the section already synthesised. The caveat is built
from what is actually missing rather than written once, so it never claims a
gap this project does not have:

    direct dependencies only — Maven resolves the transitive ones
    direct dependencies only — Maven resolves the transitive ones and one of
      these versions
    direct dependencies only — Maven resolves the transitive ones, one of these
      versions and a parent POM this checkout does not hold

A Gradle build with a `gradle.lockfile` is `.packages` with no caveat at all,
because nothing is missing from it.

## What the app showed

The pictures are in `images/`. A Maven project, a Gradle build with no lock
file and a Gradle build with one, side by side in the same section:

    Dependencies
      gradle-locked — Gradle
        commons-io    2.11.0  ·  commons-io
        gson          2.8.9   ·  com.google.code.gson
        log4j-api     2.17.1  ·  org.apache.logging.log4j
      gradle-service — Gradle
        commons-io    2.11.0  ·  commons-io
        gson          2.8.9   ·  com.google.code.gson
        direct dependencies only — Gradle resolves the transitive ones
      maven-service — Maven
        commons-lang3     3.14.0  ·  org.apache.commons
        jackson-databind  2.15.2  ·  com.fasterxml.jackson.core
        slf4j-api                    org.slf4j
        direct dependencies only — Maven resolves the transitive ones and one
        of these versions

`gradle-locked` has no note under it, and that is the point: its
`gradle.lockfile` holds `log4j-api`, which nothing in the build file mentions
— a transitive one — so there is nothing to caveat. `commons-lang3`'s version
came out of a `${commons.version}` property; `slf4j-api` has none because the
POM leaves it to a BOM, and that is the row the note is counting.

`abydos-examples/java` itself is in the second picture and reads **no
dependencies** for both of its projects, which is true: neither declares any.
That is another of the section's answers and worth having, but it is not a
picture of this item working, which is why there is a second project — a copy
of those two under /tmp with dependencies added, plus a third with a lock file.

### The caveat did not fit, and its tooltip said nothing about it

Found by looking rather than by testing, which is 0513's lesson again. The
sidebar drew

    ? direct dependencies only — Maven resolv.

and `DependencyNode.detail` for a note was `kind.title + " in " + root.path`,
so the half that was cut off was reachable from nowhere. A note's tooltip now
leads with its own message. Every other row in the section already followed
that rule — anything too long for the pane goes on the tooltip — and the notes
were outside it because until now no note had been longer than four words.

## Ruled out

- **`mvn dependency:list`, and Gradle's tooling API or `gradle dependencies`.**
  The rule on `ExternalDependencies` in `SwiftPackage`'s words, and the item
  expected Gradle to be where it finally bent. It did not have to: the lock
  file answers, and the builds that have no lock file are exactly the ones a
  daemon would take the longest on. Both cost a JVM on a synchronous path run
  once per root when a project opens and again on every write to a manifest,
  answer with whichever toolchain is on the PATH, and have side effects —
  Gradle starts a daemon that outlives the question and Maven writes into
  `~/.m2`. 0513 watched rust-analyzer do the equivalent and take seconds over
  it; nothing here needed to repeat that measurement.
- **Reading the parent POM out of `~/.m2`.** This is the tempting one, and it
  is the difference between `slf4j-api` having a version and not: the parent
  and the imported BOM are both sitting in the local repository as `.pom`
  files, and following them would fill in most of the missing versions. Not
  done, because it is resolution rather than reading — `<dependencyManagement>`
  with `<scope>import</scope>` is recursive, a POM in the repository has its
  own parent, and the chain can be missing links on a machine that has never
  built this project. It would still yield no transitives, so the caveat would
  stay; what it would buy is fewer version-less rows, and it is a whole item's
  worth of care to buy them. Somebody wanting it should start at
  `readMavenPackages`, where the chain currently stops.
- **Pointing `localPath` at the directory the jar is in.** It is a directory
  and the tree would happily list it, which is exactly the problem: the row
  would open onto `commons-lang3-3.14.0.jar`, `.jar.sha1`, `.pom` and
  `_remote.repositories`, and a package whose "sources" are four checksums
  reads as a package this program cannot open properly. The artefact is named
  on the tooltip instead and the row does not expand.
- **Unpacking `-sources.jar`, and browsing inside an archive.** Above, under
  what was decided.
- **A TOML library for `gradle/libs.versions.toml`.** Two tables of quoted
  strings, which is 0513's argument about `Cargo.lock` in a second spelling.
  `project.md` asks for an argument before a dependency is added and this is
  not one.
- **`dependencies { }` inside `subprojects { }` or `allprojects { }`.** Read at
  brace depth 0 only, which is what keeps `buildscript { }`'s plugin classpath
  out — and the same rule drops a root build that declares its modules'
  dependencies for them. That is a real Gradle layout and it will show those
  modules as having none. Reading it properly means knowing which module the
  block applies to, which is evaluating the build; the honest half was
  preferred to a list attributed to the wrong project.
- **`buildscript-gradle.lockfile`.** The locked form of the same plugin
  classpath, and left alone for the same reason.
- **A version catalog somewhere other than `gradle/libs.versions.toml`.**
  `versionCatalogs { create("x") { from(files("gradle/other.toml")) } }` is
  legal. The accessor name is read from `settings.gradle`; the file name is
  not, and a build that moves it gets no rows from its catalog.
- **Marking a dependency direct or transitive.** `gradle.lockfile` says which
  configurations resolved each one, so `runtimeClasspath` alone is a fair
  hint. Not done, for 508's reason: one list sorted by name is what makes
  thirty rows browsable, and "what is beside this file" is not answered by
  resolution order.
- **Reusing `MavenProject` for the reading.** It parses the same file, and its
  `dependencies` are bare artifactIds — no group, no version, no
  `dependencyManagement`, no parent chain. What *was* shared is the four-line
  `XMLElement` extension at the bottom of `MavenProject.swift`, made internal
  rather than copied, so the two readings of a POM cannot drift.
- **An environment variable for Maven's local repository.** There is none.
  `M2_HOME` is where Maven is installed. `settings.xml` is the only override,
  so `mavenLocalRepository(home:)` takes the home directory as a parameter and
  the test hands it a fake one — which also avoids `CARGO_HOME`'s trap, where a
  process-wide variable makes two parallel tests read each other's cache.
- **A Maven or Gradle example with real dependencies in `abydos-examples`.**
  0513's argument exactly, and it applies harder here: `~/.m2` and
  `~/.gradle/caches` are per-machine and cannot be committed, so a fixture with
  `jackson-databind` in it says nothing until somebody with a network runs the
  build. The examples are built to compile offline. The claims here are made by
  POMs and lock files written into temporary directories, and the app was
  watched against a copy under `/tmp` with dependencies whose jars are really
  in this machine's caches.

### What fails in a full run and passes alone, with three worktrees at once

Two rounds of this, and neither is this branch. First
`ToolContainerLiveTests.theSweepTakesWhatAnEarlierRunLeft`, which starts real
containers. Then, on the second full run, eighteen issues across
`PseudoTerminalWriteTests`, `TerminalTests`, `AbydosIcatTests`,
`AbydosOpenTests`, `BrokenPipesTests` and `ClaudeHookLiveTests` — every one of
them a `terminal.start(...)` or `pty.start(...)` returning false, which is a
machine that has run out of pseudo-terminals rather than a program that has
stopped working. Three sibling items were building and testing the same
repository in three worktrees at the time.

Every one of them passes on its own with `FILTER`, which is the only way to
tell the two apart. 2765 tests, `make warnings` clean.

## Steps

- [x] Decide what a JVM dependency's row shows when the sources are a jar, and
      write the answer down
- [x] A fourth reading — a list that is real and *also* incomplete — since
      `.unresolved` cannot carry one and `.packages` claims the opposite
- [x] Read a `pom.xml` project's dependencies, and say what is not resolved
      rather than showing a partial list as though it were whole
- [x] Read a Gradle project's dependencies, or write down why running Gradle is
      the only way and what that costs
- [x] `DependencyKind.pendingItem` stops naming this item for Maven and Gradle
- [x] The kind standing for "nobody has taught this one" in the tests moves off
      Maven, now that Maven is read
- [x] Watched in the app on a Maven project and a Gradle project, with a
      screenshot
- [x] A note's tooltip carries its own message, since the caveat is a sentence
      and the pane cuts it — found in the app
- [x] Write down here what was ruled out on the way
- [x] `spec/project-view.md` says Maven and Gradle are among the kinds that
      are read — not `spec/editor.md`, which predates the section; 0513 hit
      the same thing and corrected it in its own last step
