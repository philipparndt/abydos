# 512. The dependencies section cannot read Maven or Gradle

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

## Steps

- [ ] Decide what a JVM dependency's row shows when the sources are a jar, and
      write the answer down
- [ ] Read a `pom.xml` project's dependencies, and say what is not resolved
      rather than showing a partial list as though it were whole
- [ ] Read a Gradle project's dependencies, or write down why running Gradle is
      the only way and what that costs
- [ ] Watched in the app on `abydos-examples/java`, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says Maven and Gradle are among the kinds that are read
