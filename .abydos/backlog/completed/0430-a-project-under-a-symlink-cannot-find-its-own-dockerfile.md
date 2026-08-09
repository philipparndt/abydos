# 430. A project under a symlink cannot find its own Dockerfile

`DevContainerFile.relative()` compares a project root that has been through
`realpath` against a file path that has not. On macOS `/tmp` is a symlink to
`/private/tmp`, so for any project under `/tmp` or `/var` the two never share a
prefix: `shown` collapses to `devcontainer.json` with no folder in front of it,
and a `build.dockerfile` resolves to `<project>/Dockerfile` rather than to the
file the devcontainer.json actually names. The build then fails with
"dockerfile does not exist" about a file that is plainly there.

Found while proving the terminal shows a container coming up: the first
Dockerfile probe failed, and the same project built without complaint from a
normal path. So it is not rare in testing — every scratch project this app's
harness makes lives under `/tmp` — and it is invisible in ordinary use, which
is the combination that wastes an afternoon.

**The fix is to canonicalise both sides or neither**, and to say which in a
comment, because the asymmetry is the whole bug. Worth checking the other
places a project root is compared against a path the same way; `ContainerPaths`
refuses anything outside the project by exactly this kind of comparison, and a
symlinked root there would refuse a file that is inside it.

A test wants a project under a symlinked directory, which is one `ln -s` in a
temporary folder rather than anything exotic.

## Fixed, 2026-08-09

Canonical on **both** sides, in `DevContainerFile.relative()`, and the comment
there says which and why: the answer is joined back onto the canonical root by
`fileURL()` and handed to a container runtime, which knows a directory by its
real name. The two are now exact inverses. `DevContainerLiveTests` builds a
project reached through an `ln -s` and runs a command in the container it
built; before the change the same test failed with *"…/checkout/Dockerfile
would not build: failed to read dockerfile: open Dockerfile: no such file or
directory"*.

`ContainerPaths` turned out to be right already — both construction sites and
both callers pass `FilePath.canonical` — but nothing said so, so now it does,
including why the canonicalising must stay at the edge: it maps paths that need
not exist, and `realpath` cannot answer for those.

Six neighbours had the same asymmetry, each now canonical on both sides with a
sentence saying so:

- `DebugAdapters.adapter(forProgramAt:projectRoot:)` — the program's path was
  canonical (via `${workspaceFolder}`), the root was not, so the walk for a
  `go.mod` or a POM never ran and every Go program was handed to lldb.
- `DebugPane` stack frames — the adapter answers with real paths, so every
  frame fell back to its last component and two `main.go`s looked like one.
- `BazelBuild.packageLabel` — every package labelled `//`, which is not a
  label that fails but one that names a different target.
- `GitWorktrees` — git prints real paths where the project holds the opened
  one, so a project matched none of its own worktrees; standardized there, as
  `GitRepository.discover` already documents doing for `--show-toplevel`.
- `MainWindowController.fixWithAI` and `relativePathOfActiveFile`.
- `ScratchesPane.moveToProject`.

And the hole that made "both sides" hard to hold: `FilePath.canonical` falls
back to `standardizingPath` for a path that is not there yet, and that resolves
no symlinks at all — the same fault by the back door. `canonicalEvenIfMissing`
canonicalises the deepest part that does exist and puts the rest back on.

Two normalisations remain, deliberately: **canonical** (`FilePath.canonical`,
realpath) for anything handed to a tool outside the app — runtimes, debuggers,
language servers, git plumbing — and **standardized** for the file tree, the
navigator and the session store, which only ever compare the app's own names
with each other. Each is internally consistent. The bug is always a value
crossing from one to the other, so the rule is to canonicalise at that edge.

Not fixed, and worth an entry if it ever bites: `LanguageService` and
`LanguageServers` key their tables by `standardizedFileURL` while every path
they *send* is canonical. Both namespaces are consistent today, so it is not a
live fault — it is one `project.root` call site away from being one.

---

Its number is where it sits in the queue, not what it is worth doing next.
