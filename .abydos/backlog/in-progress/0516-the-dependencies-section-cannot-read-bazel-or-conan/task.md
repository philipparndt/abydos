# 516. The dependencies section cannot read Bazel or Conan

Item 508 gave the project view a **Dependencies** section: the packages a
project depends on, named rather than pathed, each with where it came from and
its sources on disk so a file opened by following a symbol can be revealed
beside its siblings.

508 taught it Swift packages and Go modules and left the rest saying so out
loud. A Bazel workspace's row in the section reads

    Bazel — not read yet (0513)

and a Conan project's says the same. This item is both, for the same reason
0512 is both Maven and Gradle: they share the one property that makes them hard.

## Why one item and not two

**Neither has a lock file this can simply read.** Every kind 508 taught, and
both kinds 0510 and 0511 propose, resolve out of a file that is already on
disk. These two resolve out of the tool:

- **Bazel** puts external repositories under `bazel-<workspace>/external/`,
  which is a symlink into an output base somewhere under
  `~/var/tmp/_bazel_<user>`, and it only exists after a build. `MODULE.bazel`
  names the direct `bazel_dep`s and `MODULE.bazel.lock` names the resolved set
  in a form that changes between Bazel releases. `bazel query
  @…//...` and `bazel mod graph` answer properly and start a server.
- **Conan** has `conan.lock` when somebody made one and `conanfile.py` — a
  Python program — when they did not. Packages land in
  `~/.conan2/p/<hash>`, addressed by a hash of the whole resolved recipe rather
  than by name and version, so the path cannot be computed from the manifest.
  `ConanProject` already refuses to execute `conanfile.py` to fill in a menu,
  and that refusal is the precedent to argue with.

So the decision both of them need is the same one: **does this section ever run
the build tool?** So far nothing in this program does — `SwiftPackage`,
`XcodeProject`, `BazelBuild` and `ConanProject` all read text instead, and the
reasons are written down in `SwiftPackage`'s own comment. If the answer stays
no, these two kinds keep a note of a different shape — "needs a build to say"
rather than "not read yet" — and that is a legitimate finish for this item.

## Where the work goes

`Sources/AbydosKit/Project/ExternalDependencies.swift` — `case bazel` and
`case conan` in `DependencyKind`. The section, the reveal and the sibling
browsing are already built and kind-agnostic.

## What was read before anybody started, and not verified

An agent read the ground and stood down without writing code. None of it has
been compiled or watched; the cache layouts especially are the part most likely
to be wrong.

**The decision this item turns on, answered: no, and for stronger reasons than
cost.** Conan is settled by *do not execute the project* — `conanfile.py` is a
Python program out of somebody's repository and `conan graph info` evaluates
it; `ConanProject` already refuses that to fill a menu, and filling a tree row
is not a better reason. Bazel is settled by *the lock, not the second* —
`bazel query` starts a server that takes a lock on the output base, so the
section would block behind somebody's build or make their next `bazel` command
block behind the section, on a path that runs on project open and on every
write. Also bazel need not be installed, and bazelisk's first run downloads a
release, so opening a project would trigger a package fetch.

**But both are readable further than this item assumes, without a subprocess.**

*Bazel.* `MODULE.bazel.lock` is JSON with two layouts: 7.0/7.1 wrote
`moduleDepGraph`, the whole resolved set; 7.2+ dropped it for
`registryFileHashes`, where the **selected** set is the keys ending
`/source.json` — the `…/MODULE.bazel` keys include versions only *considered*,
so reading those lists three versions of one module. Neither layout is promised,
so an unreadable lock should come back empty rather than error. `MODULE.bazel`
is the fallback — `bazel_dep(name:version:)`, direct only, exact — and
`BazelBuild.declarations`/`stripComment` already do most of it;
`nameAttribute` wants generalising to read `version` too, and scanning *every*
occurrence of the key on a line rather than the first, which today finds the
word inside a quoted string and gives up. Sources: `bazel-<workspace>` is a
symlink into `<output base>/execroot/<ws>`, repositories at
`<output base>/external` — resolve the symlink, walk up to the component named
`execroot`, take its parent; do **not** compute the output base, it is an md5.
Repo directory names carry a separator that changed between releases
(`rules_go~0.50.1`, `rules_go+0.50.1`, `rules_go+`, plain), so list and match —
cargo's registry-hash wall again.

*The genuine "not read" is `WORKSPACE`-only*: its repositories are Starlark, and
listing `external/` does not rescue it, because after a build that directory is
mostly Bazel's own autoconfiguration repos and nothing on disk tells those from
the declared ones.

*Conan.* `conan.lock` (Conan 2) is JSON — `requires`/`build_requires`/
`test_requires`, each `name/version@user/channel#revision%timestamp`. A Conan 1
lock parses as JSON with none of those keys, so guard on the keys or it reads as
"no dependencies", the exact lie this section exists to prevent.
`conanfile.txt` is data, not a program. A `conanfile.py` with no lock is the
honest unresolved case — `no conan.lock — run conan lock create .`, noting
`conan install` does not write one by default in Conan 2. **Do not** scrape
`self.requires(…)` out of the recipe: requirements are routinely conditional on
options and settings, so the list would be complete for some projects and
quietly short for others with no way for the row to say which. Sources:
`$CONAN_HOME` else `~/.conan2`, packages at `p/b/<name><hash>/p` — the recipe
folder `p/<name><hash>` holds the recipe, not the library. Match strictly:
require the remainder after the name to be non-empty and all hex, or `fmt`
matches `fmtlog`'s folder and the row opens another package's headers.

**An environment note for whoever picks this up.** The agent that read this
found `swift build`, `make test` and `swift package resolve` all denied in its
sandbox, no network, and neither `bazel` nor `conan` installed. If that holds,
this item cannot be compiled, tested or watched against a real project from
there — worth establishing before planning the work rather than after.

*Checked first thing, and it does not hold here.* `make build JOBS=4` compiles
and assembles `build/Abydos.app`, and `make test` runs. Neither `bazel` nor
`conan` is installed on this machine, though, so the two **cache layouts are the
one part of this that no run here can confirm** — every claim about
`<output base>/external` and `~/.conan2/p` is made against a directory tree
written by hand to match the documented shape. Both readers are built so that a
wrong guess costs a row its sources and nothing else: the package still appears,
with its name, version and origin, and simply cannot be opened.

**Two smaller things.** `MODULE.bazel.lock` and `conan.lock` are already in
`ExternalDependencies.definingFileNames`. And `spec/project-view.md`'s
requirement "A kind of project this cannot read says so, on a row" promises an
unresolved note *in the words of the tool that would resolve it* — the
`WORKSPACE` case has no such command, so that requirement wants modifying
rather than joining.

## Estimate

2026-08-17 09:10 — about three hours left

## Steps

- [x] Establish whether this can be built and tested here at all, before
      planning work nobody can check
- [x] Decide whether this section may run a build tool, and write the answer
      down — it is the decision both kinds need and neither can start without
- [x] Read a Bazel workspace's externals, or say exactly why a build is needed
      first
  - [x] `MODULE.bazel.lock`, both layouts, taking the *selected* set rather
        than every version considered
  - [x] `MODULE.bazel` as the fallback, the direct `bazel_dep`s
  - [x] The sources under the output base, found by listing the repository
        directories rather than computing their names
- [x] Read a Conan project's packages, or say exactly why the recipe has to run
  - [x] `conan.lock`, guarded on its keys so a Conan 1 lock is not read as
        "no dependencies"
  - [x] The package's files in the Conan 2 cache, matched strictly enough that
        `fmt` does not open `fmtlog`'s folder
- [x] `DependencyKind.pendingItem` stops naming this item for Bazel and Conan
- [x] Say what stays honestly unread, and what its row says instead
- [ ] Watched in the app, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/project-view.md` says what Bazel and Conan projects show
