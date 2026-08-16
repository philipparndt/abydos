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

- **How far this goes.** Swift packages have `Package.resolved`; Maven, Gradle,
  Go, Cargo and npm each have their own answer, and this repository opens all of
  them. One language's dependencies is a small item and a section that lies for
  every other language; all of them at once is a large one. Where the first
  version stops is the main decision.
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

## Steps

- [ ] Decide how far the first version goes — which project kinds, and package
      list against file tree — and write the answer down
- [ ] A section in the project view for what the project depends on
- [ ] It says where each one came from, from what is already on disk
- [ ] A file opened by following a symbol can be revealed in it
- [ ] Its siblings can be browsed from there
- [ ] It says which subproject a dependency belongs to, where there is more than
      one
- [ ] Decide what happens to `.build` in the ordinary tree, and say why
- [ ] Watched in the app, with a screenshot of a dependency revealed
- [ ] Write down here what was ruled out on the way
- [ ] The spec says what the project now does
