# 527. A Bazel workspace or a Conan project inside a repository is not a subproject

`Subprojects.markers` is the list of files that make a folder inside a project
a project of its own. It has thirteen entries — `.git`, `go.mod`, `Cargo.toml`,
`package.json`, `pom.xml`, `build.gradle`, `Package.swift`, `CMakeLists.txt`,
`Makefile` and four more — and it has neither `MODULE.bazel` nor `WORKSPACE`
nor `conanfile.py` nor `conanfile.txt`.

So a repository holding `services/build-farm/MODULE.bazel` has no subproject
there. Nothing scoped follows it: no scope pill, no run configurations of its
own, no language-server root, and — since 0516 — no row in the **Dependencies**
section, however well its `MODULE.bazel.lock` can now be read. Opening the
workspace directly as the project works, which is what 0516's pictures show;
the gap is only for one nested inside something else.

Found while doing 0516, which read both kinds and then could not photograph
them side by side in one repository because neither folder counted as a
subproject.

## Why it was not just fixed there

`Subprojects` is not only the dependencies section's list. It decides which
folder the scope pill names, which root a language server is started on, which
module a run configuration builds in and which tree git acts on. Adding two
markers changes all of those at once, and each of them has requirements in the
spec that would need checking. That is a change with its own argument to make
and its own things to watch in the app, not a line inside an item about reading
lock files.

There is also a judgement to make that 0516 had no business making alone.
`MODULE.bazel` is safe — a repository has one per workspace. `WORKSPACE` is
nearly as safe. `conanfile.txt` is the doubtful one: it turns up in an
`examples/` folder beside a recipe, and a folder that is only a list of
dependencies for somebody's sample may not be worth a scope of its own.

## The decision

**Three of the four go in, and `conanfile.txt` stays out.** `MODULE.bazel`,
`WORKSPACE` and `conanfile.py` are in `Subprojects.markers` — and with them
`WORKSPACE.bazel` and `WORKSPACE.bzlmod`, because `BazelBuild.workspaceMarkers`
and `DependencyKind.bazel.markers` already name all four and a list that took
two of them would make a workspace's scope depend on which spelling it used.
The list is spliced from `BazelBuild.workspaceMarkers` rather than copied, so
the two cannot drift.

The argument for `conanfile.py` and against `conanfile.txt` is not about how
often either turns up. It is what the file *claims*:

- A **recipe** is the package. It names it, it is what `conan create` builds,
  and `ConanProject` already treats it as the project — the recipe wins over a
  `conanfile.txt` beside it. A folder holding one is a project with nothing
  else in it, which is exactly what a header-only recipe is.
- A **`conanfile.txt`** says only what a directory *consumes*. It declares no
  package and builds nothing; `ConanProject` offers it `install` and nothing
  else, for that reason. It is what Conan's own layout puts in an `examples/`
  folder beside a recipe.

And excluding it costs almost nothing, which is what settled it: a directory
that is genuinely a project *and* consumes Conan packages has the
`CMakeLists.txt` or the `Makefile` that says so, and is a subproject by that
marker already — at which point `ExternalDependencies.kinds(at:)` gives it its
Conan row anyway, because that function reads the directory itself and does not
consult this list. So the only thing kept out is a folder whose sole
build-system file is a list of somebody's sample's dependencies, which is the
case the item was doubtful about. Tested both ways round:
`aConanfileTxtOnItsOwnIsNotAProject` and
`aConanfileTxtBesideABuildFileIsFoundByTheBuildFile`.

## The false positive that nearly shipped with `WORKSPACE`

`isSubproject` asked `FileManager.fileExists(atPath: …/WORKSPACE)`, and **a Mac
formats a disk case-insensitively by default**, so that returns true for any
folder holding an ordinary `workspace/` directory — measured, not assumed. Every
Eclipse checkout, every `workspace/` somebody made by hand, would have got a
scope pill, a language-server root of its own and a Bazel group row saying its
dependencies were Starlark. That is precisely the failure worth more than the
gap being fixed, so the marker check now reads the directory's names once and
compares them exactly (`FilePath.entryNames(in:)`), and
`ExternalDependencies.kinds(at:)` was moved onto the same footing because it had
the identical bug.

Exact matching also means `Makefile` no longer matches a lowercase `makefile` by
accident, so `makefile` and `GNUmakefile` are named explicitly — the three names
`RunConfigurationDiscovery.definingFileNames` already lists. That keeps today's
behaviour on a case-insensitive disk and gives it to a case-sensitive one for
the first time.

## What else the change moves, checked

`Subprojects` feeds more than the dependencies section, so each was followed:

- **The scope pill and the subproject menu** — `showSubprojectMenu` lists
  `Subprojects.find`, so this is the half that was missing. Watched:
  `images/0527-scope-bazel.png` and `images/0527-scope-conan.png`.
- **The dependencies section** — `ExternalDependencies.roots` is
  `[project] + Subprojects.find`. Watched: `images/0527-deps-section.png`, with
  `native/fmt — Conan` and `services/build-farm — Bazel` on group rows of their
  own, and `samples/` (a lone `conanfile.txt`) and `eclipse/` (a `workspace/`
  folder) on none.
- **The language-server root** — `applyScope` calls
  `LanguageService.shared.warmUp(project: scope)` and everything else reads
  `project.scopeRoot`. Nothing in `spec/language-servers.md` constrains which
  folders may be a root: "One server per project per server" is keyed by the
  root it is given, and a nested workspace being one more possible root does not
  touch it.
- **Run configurations** — worth writing down, because it is not what the
  comment on `launchRoot` suggests. **Discovered** configurations come from
  `RunConfigurationDiscovery.discover(in: project.root)` and are not scoped at
  all; scoping moves only where *saved* ones are read and written
  (`LaunchStore.read(in: launchRoot)`). Confirmed with `--run-configs` on the
  whole project and scoped to each of the two: the same five Conan actions, all
  of them found three directories deep from the root either way. So nothing in
  `spec/run-configurations.md` changes — "build files are looked for three
  directories deep" is still the whole story.
- **The git tree** — `applyScope` re-reads git for the scope, and
  `GitRepository.discover(from: scope ?? root)` walks *up*, so a nested folder
  with no `.git` of its own still finds the repository above it. The branch pill
  still reads `main` in both scoped pictures.
- **The terminal** — `bottomPanel.setWorkingDirectory(scope)`; `--report-cwd`
  reports `subproject=build-farm` while scoped.
- **The session** — `subprojectPath` is written relative and resolved by
  `Subprojects.resolve`, which checks existence and containment and not the
  markers, so nothing in `spec/sessions.md` moves.

## Ruled out

- **Following symbolic links.** A built Bazel workspace has `bazel-out`,
  `bazel-bin` and `bazel-<workspace>` beside its `MODULE.bazel`, and the last is
  the execroot, whose top level mirrors the source tree — `MODULE.bazel`
  included. That would be the workspace offered as a subproject of itself. It
  cannot happen: `.isDirectoryKey` is **false** for a symbolic link whatever it
  points at (measured), so `walk` already skips every one. Nothing needed
  changing; the reason is now written where the guard is.
- **`test_package/conanfile.py`.** A Conan recipe conventionally carries one,
  so `conanfile.py` is not strictly one per project. Left as a subproject: a
  `test_package` is a small buildable project of its own, it already had a
  `CMakeLists.txt` and was therefore already a subproject before this item, and
  refusing it by name would be a special case earning nothing.
- **`getattrlist` / `canonicalPath` for the case check.** Both answer the
  case question in one syscall — `canonicalPath` measured *faster* than
  `fileExists` — and both resolve symbolic links, so a marker that is a link to
  a differently named file would stop counting. Reading the directory's names is
  slower in the worst case and is the same question the caller is actually
  asking, so it won.
- **Adding a delta to `run-configurations.md` or `language-servers.md`.** Both
  were read for a requirement this change makes untrue, and neither has one:
  they are written in terms of "the project" and "the scope", and what may *be*
  a scope had never been written down anywhere. That is the gap the delta fills,
  in `project-view.md`, which is the file that already talks about subprojects.

## Steps

- [x] Decide which of the four markers belong in `Subprojects.markers`, and
      write down why `conanfile.txt` is or is not one of them
- [x] The dependencies section shows a nested Bazel workspace and a nested
      Conan project, each on a group row of its own
- [x] Check what else the change moves: the scope pill, the language-server
      root, run configurations, the git tree
- [x] Watched in the app on a repository with one of each nested in it
- [x] A marker is matched by name and not by asking a case-insensitive file
      system, so a `workspace/` folder is not a Bazel workspace
- [x] Write down here what was ruled out on the way
- [x] `spec/project-view.md` — and whichever other capability the scope change
      touches — says what the project now does

## Estimate

2026-08-17 14:43 — done bar a final test run
