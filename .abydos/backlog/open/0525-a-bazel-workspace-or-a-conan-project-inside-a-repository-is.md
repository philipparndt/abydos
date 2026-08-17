# 525. A Bazel workspace or a Conan project inside a repository is not a subproject

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

## Ruled out

Nothing yet. 0516 established the gap and stopped there deliberately.

## Steps

- [ ] Decide which of the four markers belong in `Subprojects.markers`, and
      write down why `conanfile.txt` is or is not one of them
- [ ] The dependencies section shows a nested Bazel workspace and a nested
      Conan project, each on a group row of its own
- [ ] Check what else the change moves: the scope pill, the language-server
      root, run configurations, the git tree
- [ ] Watched in the app on a repository with one of each nested in it
- [ ] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` — and whichever other capability the scope change
      touches — says what the project now does
