# 508. A file outside the project has no place in the project view

> I think we need a section with projects and subprojects where virtual content
> is shown, like external dependencies. When navigating to them, there is
> currently no way, to reveal them in the project view and browse siblings, see
> where they come from, …

Go to a definition in a dependency and the file opens — `Extrusion.swift` from
Cadova, in the screenshot with the report, arrived by following a symbol out of
somebody's own model. It opens with a `↗` on the tab, which says it is from
outside. And there it stops. The project view cannot show it, so there is no way
to see what is beside it, which package it belongs to, or where that package came
from.

The tree today is the project's own directory, and a checkout under `.build` is
either invisible or — as the screenshot shows — an ordinary folder called
`.build` with no more meaning than any other, sitting inside the subproject that
happens to have built it.

## What is being asked for

A section in the project view for things that are **not** the project's own
files: its dependencies, resolved and named as packages rather than as paths.
IntelliJ's *External Libraries*, and Xcode's *Package Dependencies*. Enough that
a file opened by following a symbol can be revealed in it, its siblings browsed,
and its origin read off.

## What exists to build on

- **Subprojects are already a concept.** The screenshot shows `abydos-examples`
  open with `cadova-models` inside it, and the titlebar carries a subproject
  chip; `--subproject` is a launch option and `scopeRoot` is the thing it sets.
  Whatever section this becomes has to say which subproject a dependency belongs
  to, because two of them may resolve different versions of the same package.
- **The resolved graph is already readable.** `Package.resolved` names every
  package, its URL and its revision — 0500 committed one deliberately. That is
  "where it comes from", already on disk, no subprocess.
- **`SwiftPackage` reads manifests as text** (0498), so the dependency *names*
  are available without building anything.
- **Reveal exists** for files in the project, and 0463's footer chip is the
  precedent for saying where something came from in a small space.

## Worth deciding, and there is a lot of it

- **How far this goes — decided: all of them.** Asked directly, Philipp answered
  "it shall support all external dependencies", on 2026-08-16. So this is the
  large version: Swift packages have `Package.resolved`, and Maven, Gradle, Go,
  Cargo and npm each have their own answer, and this program opens all of them.
  What is still open is the *order* and what an unsupported kind does — a
  section that silently omits a project's dependencies is the failure to avoid,
  so a kind not yet read should say it is not read rather than show nothing.
- **Whether it is a tree of files or a list of packages.** Browsing siblings
  needs the files; seeing where something came from needs the package. They are
  different views of the same thing and the item asks for both.
- **What "reveal" means for a file with no place in the tree.** Today reveal
  selects a row. A dependency's file has no row until this section exists, and
  it may have none afterwards either if the section is a list of packages rather
  than a tree.
- **Whether `.build` stops being an ordinary folder.** It is a checkout
  directory that happens to be inside the project. If dependencies get a section
  of their own, showing `.build` as a plain folder as well is showing the same
  thing twice — and hiding it is a decision about somebody else's directory.

## How far the first version goes — decided

"All external dependencies" is eight build systems, and eight readers written
in one sitting would be seven of them written without ever being looked at.
What ships here is **the frame plus two kinds**, and the rest is filed as items
of its own — which is only honest because **a kind that is not read says so, on
a row, in the section**. That is the whole of what makes a split legitimate: a
Maven project does not show an empty Dependencies section that reads as "this
project has none". It shows

    Maven — not read yet (0512)

with the number of the item that will do it. Somebody looking at the app knows
what is missing and where it is written down; nobody has to go and read the
backlog to find out that the section is lying to them.

### The two kinds, and why those two

- **Swift packages.** The case in the report. `Package.resolved` is JSON on
  disk, names every package with its location and the version it settled on,
  and the sources are already fetched into `.build/checkouts`. No subprocess,
  nothing to install, and a fixture — `abydos-examples/cadova-models` — that
  0500 committed on purpose.
- **Go modules.** Chosen as the second *because it is not shaped like the
  first*, which is the only way to find out whether the frame is a frame or a
  Swift feature with a section drawn round it. Three differences, all of which
  the frame had to grow to hold: the origin is a module path rather than a URL,
  there is no lock file at all — `go.mod` is the manifest and the resolved set
  at once — and the sources are **not inside the project**: they are in the
  module cache under `~/go/pkg/mod`, addressed by a name that has to be escaped
  (`github.com/IBM/…` → `github.com/!i!b!m/…`). That last one is the item's
  real subject — a file with no place in the tree — in its hardest form, and a
  Swift-only version would never have met it.

### The rest, filed

| Kind | Item | Why it is not here |
| --- | --- | --- |
| Cargo | 0510 | `Cargo.lock` is TOML and there is no TOML reader here; the registry directory has a hash in its name and has to be listed |
| npm, pnpm, yarn | 0511 | Three lock files and three layouts, and `node_modules` is the one cache that is *inside* the project |
| Maven, Gradle | 0512 | One item, not two: the JVM resolves to **jars**, not sources, and what a package row shows when there is nothing to browse is one decision made once for both |
| Bazel, Conan | 0513 | One item, not two: neither resolves out of a file that is already on disk, so both need the same answer to "may this section run the build tool?" — which so far nothing in this program does |

### A list of packages, and a tree of files, and not a choice between them

The item asked which it was. It is both, and the join is what makes it cheap: a
package row *is* a directory, so its children are ordinary `FileNode`s and
everything the tree already does — lazy listing, git colour, the context menu,
reveal, arrow keys — works inside a dependency without a line written for it.
The package row carries the name, the version and the origin; the rows under it
are the files.

## Estimate

2026-08-16 19:30 — most of a day left

## Steps

- [x] Decide how far the first version goes — which project kinds, and package
      list against file tree — and write the answer down
- [x] File the kinds that are not in this item: 0510, 0511, 0512, 0513
- [ ] Read a project's dependencies, from what is already on disk
- [ ] A section in the project view for what the project depends on
- [ ] It says where each one came from, from what is already on disk
- [ ] A kind that is not read says so, rather than showing nothing
- [ ] A file opened by following a symbol can be revealed in it
- [ ] Its siblings can be browsed from there
- [ ] It says which subproject a dependency belongs to, where there is more than
      one
- [ ] Decide what happens to `.build` in the ordinary tree, and say why
- [ ] Watched in the app, with a screenshot of a dependency revealed
- [ ] Write down here what was ruled out on the way
- [ ] The spec says what the project now does
