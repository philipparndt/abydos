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

## Steps

- [ ] Decide what a JVM dependency's row shows when the sources are a jar, and
      write the answer down
- [ ] Read a `pom.xml` project's dependencies, and say what is not resolved
      rather than showing a partial list as though it were whole
- [ ] Read a Gradle project's dependencies, or write down why running Gradle is
      the only way and what that costs
- [ ] Watched in the app on `abydos-examples/java`, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` says Maven and Gradle are among the kinds that
      are read — not `spec/editor.md`, which predates the section; 0513 hit
      the same thing and corrected it in its own last step
