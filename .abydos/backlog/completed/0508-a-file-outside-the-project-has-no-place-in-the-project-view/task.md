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

## What was found on the way

The pictures are in `images/`.

### The file in the tab was never the file this item thought it was

**This is the finding worth the whole day, and nothing but running the app
would have produced it.** The report says `Extrusion.swift` opened "from
Cadova's own sources, under `.build/checkouts`", and everything here was built
against that: the reader looked in `<root>/.build/checkouts/<name>`, a fixture
proved it, seventeen tests passed.

Then `--definition` was pointed at `.extruded(…)` in a real model, and the
editor opened

    ~/Library/Caches/abydos/index/cadova-models-mn5raibyyd7h/checkouts/
        Cadova/Sources/Cadova/…/ExtrudeWithEdgeProfiles.swift

`LanguageServers.arguments(for:root:)` starts sourcekit-lsp with
`--scratch-path` under the caches — deliberately, because an index inside the
checkout is one more thing to ignore and one more thing to search by accident —
and SwiftPM fetches its **own copy of every dependency** beneath it. So there
are two checkouts of the same revision on this machine, and the one the editor
opens is not the one in the project. A section that knew only about `.build`
gave the file in the tab no home at all, which is precisely the failure being
fixed, and it looked completely correct against every fixture.

`ExternalDependency` therefore carries `localPath` — the copy the section
*shows*, the indexer's when it exists — and `otherPaths`, the copies it will
still recognise. A file opened from either resolves to the row the section is
drawing, so its siblings are the siblings it shows.

### And a third answer, which has no place in a tree at all

Once sourcekit-lsp has finished indexing, the same `--definition` stops
answering with a source file and answers with a **generated interface**:

    /var/folders/…/T/sourcekit-lsp/GeneratedInterfaces/706881…/Cadova.swiftinterface

That is a synthesised file in a temporary directory. It belongs to no checkout,
has no siblings, and cannot be revealed anywhere. Left alone deliberately: the
section is about packages on disk, and a generated interface is not one. Worth
knowing that the same gesture produces two quite different kinds of destination
depending on whether the index is warm.

### `.build` stays an ordinary folder — decided

The item asked whether it should stop being one. It does not, for three
reasons, and the third is the one that settles it:

1. **`.build` is not only checkouts.** It holds `debug`, `artifacts`,
   `arm64-apple-macosx`, a build database. Hiding the folder to avoid showing
   the checkouts twice would hide four things that are shown nowhere else.
2. **It is somebody else's directory.** The tree is the directory; a file
   manager that quietly omits a folder because a derived view happens to also
   show part of it is a file manager nobody can trust. It is already marked —
   `FileNode.defaultExcludedDirectoryNames` tints it, and Settings can change
   that — and being marked is the honest treatment.
3. **The duplicate never gets in the way, because reveal prefers the
   section.** That is the rule that makes leaving `.build` alone free: a path
   inside any known checkout is revealed in Dependencies, so `.build` is never
   opened by the act of following a symbol. Written the other way round first,
   and the difference is visible: the ordinary tree answered, and the pane
   showed `.build ▸ checkouts ▸ Cadova ▸ Sources ▸ Cadova ▸ Abstract Layer ▸
   Operations ▸ Extrude ▸ Extrusion.swift` — ten levels of a folder nobody
   asked about, ending at the one row that cannot say which package it is.

### The section is read before the first paint, not after it

It was queued behind the first paint at first, on the argument that the rows
somebody clicks matter more than a section nobody has scrolled to. That lost a
race: `abydos --file …/checkouts/…/Extrusion.swift` opens the tab in the same
turn of the run loop, the reveal finds no section to put the file in, and the
ordinary tree answers instead. Reading it in `load(project:)` costs a
two-deep directory walk and a JSON parse per subproject, which `LaunchClock`
now reports beside the rest of the open.

## Ruled out

- **A section of its own, below the tree, in a second outline view.** The
  sidebar has been a split and was made one view again (0506 has the history),
  and a second view would need its own selection, its own keyboard, its own
  reveal. A second *root* in the same outline view — which is where IntelliJ
  puts External Libraries — costs one `numberOfChildrenOfItem(nil)` returning
  two and nothing else.
- **A list of packages with no files under it.** It would have answered "where
  did this come from" and not "what is beside it", and the item asks for both.
- **A tree of files with no package rows.** The mirror of the same mistake.
- **Marking Go's indirect dependencies.** `// indirect` is right there in
  `go.mod` and it was written and then taken out again: sorting direct-first
  breaks the alphabetical order, and alphabetical order is what makes a list of
  thirty modules browsable — which is the question being asked of it. One list,
  sorted by name, the same shape as every other kind.
- **Making a dependency's files read-only in the tree.** Rename and Move to
  Trash are offered on a file inside a package, and they would act on somebody
  else's checkout. Not done here: the same is already true of those files via
  `.build`, so this item adds a route to a hazard rather than the hazard, and
  a read-only notion in the tree is a feature of its own with its own edges
  (a `.build` copy is regenerable, a `~/go/pkg/mod` one is shared between every
  project on the machine). Left as a step below, unticked, so it is visible.
- **Running any build tool to answer.** Nothing here does, for the reasons
  `SwiftPackage`'s comment measures. It is what makes 0512 and 0513 hard and
  they say so.
- **Deleting the 1424 build artefacts sourcekit-lsp left in
  `abydos-examples/cadova-models`.** Found while watching this work; filed as
  0515 rather than swept up, since the cause is not understood and the
  sweeping is somebody else's repository.

## Steps

- [x] Decide how far the first version goes — which project kinds, and package
      list against file tree — and write the answer down
- [x] File the kinds that are not in this item: 0510, 0511, 0512, 0513
- [x] Read a project's dependencies, from what is already on disk
- [x] A section in the project view for what the project depends on
- [x] It says where each one came from, from what is already on disk
- [x] A kind that is not read says so, rather than showing nothing
- [x] A file opened by following a symbol can be revealed in it
- [x] Its siblings can be browsed from there
- [x] It says which subproject a dependency belongs to, where there is more than
      one
- [x] Find where a symbol followed out of a model *actually* lands, rather than
      where the report says it does
- [x] Decide what happens to `.build` in the ordinary tree, and say why
- [x] Watched in the app, with a screenshot of a dependency revealed
- [ ] Make a dependency's files read-only in the tree

      Not done, and not by oversight. Rename and Move to Trash are offered on a
      file inside a package and would act on somebody else's checkout — but
      that is already true of the same files through `.build`, so this item
      adds a route to the hazard rather than the hazard, and read-only in the
      tree is a feature with edges of its own. Left here rather than deleted so
      that it is somebody's to pick up.

- [x] Write down here what was ruled out on the way
- [x] The spec says what the project now does — `spec/project-view.md`, a
      capability nothing had yet
