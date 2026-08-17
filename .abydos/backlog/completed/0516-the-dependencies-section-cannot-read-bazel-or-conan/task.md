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

## What was found on the way

The pictures are in `images/`. A Bazel workspace's section now reads

    Dependencies — Bazel
      gazelle     0.38.0   ·  bcr.bazel.build
      platforms   0.0.10   ·  bcr.bazel.build
      rules_go    0.50.1   ·  bcr.bazel.build

and a Conan project's

    Dependencies — Conan
      cmake     3.29.3
      fmt       10.2.1
      spdlog    1.14.1
      zlib      1.3.1

A `.bzl` opened from `<output base>/external/rules_go+0.50.1/go/def.bzl` is
revealed on the `rules_go` row with `private/` beside it, and `fmt/format.h`
from the Conan cache on the `fmt` row with `core.h` beside it. Nothing was
written for either: 508's rule that a package row *is* a directory did all of
it, the same as 0513 found.

The Conan rows carry a version and no origin, and that is the honest answer
rather than a gap. A lock file records no remote — `conancenter` on every row
would be a guess dressed as provenance — so the only origin printed is the
`@user/channel` of a reference that has one. `spdlog` and `cmake` have no
expander in the picture and `zlib` does, which is the row saying it knows about
a package nobody has fetched here.

### The decision, and why it came out firmer than the cost rule

The section already refuses subprocesses on cost: `swift package dump-package`
is most of a second, and this runs on open and on every write. For these two the
cost argument was not the one that decided it.

- **Conan is settled by *do not execute the project*.** `conan graph info`
  evaluates `conanfile.py`, which is a Python program out of somebody's
  repository. `ConanProject` already refuses to run it to fill in a menu, and
  filling in a tree row is not a better reason than that was.
- **Bazel is settled by *the lock, not the second*.** `bazel query` starts a
  server, and the server takes a lock on the output base. The section would
  block behind somebody's build, or their next `bazel` command would block
  behind the section — on a path that runs when a project opens and again on
  every write. Slow is a trade; taking somebody's build lock is not. Bazel also
  need not be installed, and bazelisk's first run downloads a release, so
  opening a project would trigger a package fetch.

### Both read further than this item assumed

The item was filed believing neither had a file to read. Both do.

- `MODULE.bazel.lock` is the resolved set, in two layouts. **The trap in the
  7.2+ one is real and would have shipped**: `registryFileHashes` lists every
  registry file consulted, and minimal version selection fetches the
  `MODULE.bazel` of every candidate to compare them. Three versions of
  `rules_go` are named in the demo lock and one of them is the dependency. The
  keys ending `/source.json` are the selected set; a reader taking every key
  draws three rows for one module and claims all three.
- `MODULE.bazel` is the fallback when nobody has built yet — direct
  dependencies only, which is less than the lock and is not nothing.
- `conan.lock` is JSON, and **a Conan 1 lock parses cleanly with none of Conan
  2's keys**. Guarded on the keys, so an old lock says so rather than drawing
  `no dependencies` over a project with forty of them. Anything that is neither
  says it could not be read, which is the third branch that keeps every one of
  them true.

### The two that stay unread, and what they say

- **A `WORKSPACE`-only workspace.** Its repositories are declared by Starlark
  macros and no file on disk lists them. Listing `<output base>/external` does
  not rescue it: after a build that directory is mostly Bazel's own
  autoconfiguration repos and nothing there tells those from the declared ones.
  The row reads `WORKSPACE dependencies are Starlark — nothing on disk lists
  them` and **names no command**, which is why `spec/project-view.md` needed
  modifying rather than joining: it promised the note in the words of the tool
  that would resolve it, and here no such command exists.
- **A `conanfile.py` with no lock**, which reads `no conan.lock — run conan
  lock create .` — worded around the fact that `conan install` does *not* write
  one in Conan 2.

### The note was cut off, and only the app said so

`WORKSPACE dependencies are Starlark — nothing on disk lists them` came out in
the pane as `WORKSPACE dependencies are…`, and a note's tooltip was carrying
only which kind it was. So the sentence had nowhere to be read. The tooltip now
leads with the message, which fixes every note in the section — `no
Package.resolved — run swift package resolve` was being cut in the same place
and nobody had looked.

### Bazel and Conan projects are not found as subprojects — filed, not fixed

`Subprojects.markers` has `pom.xml`, `package.json`, `go.mod` and nine others
and has neither `MODULE.bazel` nor `conanfile.py`. So a Bazel workspace *inside*
a repository is not a root this section asks about, and its dependencies are
invisible however well they are read. Opening the workspace itself works, which
is what the pictures show.

Not fixed here on purpose: `Subprojects` decides the scope pill, which root the
language server is given, which module a run configuration builds in and which
tree git acts on. Adding two markers to it is a change to all of those and wants
its own item rather than a line in this one. Filed as 0527.

## What was ruled out

- **Running the build tool.** Both arguments above. This is the question the
  item was filed on and the answer is no for each kind separately, so neither
  reason has to carry the other.
- **Scraping `self.requires(…)` out of a `conanfile.py`.** Tempting, and it
  would have given the fresh-conan row a list. Requirements are routinely
  conditional on options and settings — the demo recipe has one behind
  `self.options.with_tests` — so the scraped list is complete for some projects
  and quietly short for others, with nothing on the row able to say which. A
  list that is sometimes short is worse than a row saying it does not know:
  that is this section's founding argument, wearing a list of packages as a
  disguise.
- **Reading `conanfile.txt`'s `[requires]` instead of the lock.** It is data
  and not a program, so it could be read — but it says `fmt/10.2.1` where it
  says anything at all and `fmt/[>=10 <11]` where it does not, and it has no
  transitive dependencies in it. The lock is the resolved graph, which is the
  same reason `Package.resolved` is read rather than `Package.swift`.
- **Computing the Bazel output base.** It is an md5 of the workspace path,
  under `/var/tmp/_bazel_<user>`. The convenience symlink Bazel leaves in the
  workspace points into it, so it is followed instead — any of `bazel-out`,
  `bazel-bin` or `bazel-<workspace>` will do, since all three run through
  `execroot`.
- **Hard-coding the repository directory separator.** The same module has been
  `rules_go~0.50.1`, `rules_go+0.50.1`, `rules_go+` and plain `rules_go` across
  releases. Listed and matched, with the character after the name required to be
  a separator — otherwise `rules_go` takes `rules_google+9.9`'s directory and the
  row opens a stranger's sources. 0513's registry-hash lesson in another
  spelling, and the Conan cache is the third: its folder is named for a hash of
  the whole resolved package, so `fmt` is matched only where the remainder is
  non-empty and entirely hexadecimal — a bare prefix gives it `fmtlog`'s folder.
- **Marking a Bazel module direct or transitive.** `MODULE.bazel` has the direct
  set and the lock has the whole one, so the difference is known. Not shown, for
  508's reason: one list sorted by name is what makes the section browsable, and
  "what is beside this file" is not answered by how the module was reached.
- **Erroring on a lock this cannot parse.** Neither lock format is promised
  between releases. An unreadable `MODULE.bazel.lock` falls through to the
  manifest, which lists less rather than nothing.
- **A Bazel or Conan fixture in `abydos-examples`.** Same as 0513's answer for
  Cargo, and harder: the external repositories and the Conan cache are
  per-machine, cannot be committed, and would need `bazel` or `conan` installed
  plus the network to appear at all. The claims here are made by lock files
  written into temporary directories, and the app was watched against projects
  under `/private/tmp` with a hand-built output base and cache.

### The suite went red in three places, and none of them was this

`make test` was green at 2760 and then failed in `PseudoTerminalWriteTests`,
`BrokenPipesTests` and `TmuxPasteTests` — all on `terminal.start(…) → false`
with `master → -1`, and each passing when run alone. `kern.tty.ptmx_max` is 511
and `lsof /dev/ptmx` showed 443 orphaned `/bin/cat` holding ptys, the oldest
started five days ago: `PseudoTerminalWriteTests` leaks its children and the
machine had finally crossed the limit. Clearing them took the suite to 2761
passed with nothing else changed. Filed as 0526 — it is not this branch's, and
0513 met the same shape of thing when a suite failure turned out to be somebody
else's uncommitted edit.

### What no run here could confirm

Neither `bazel` nor `conan` is installed on this machine. The lock parsing is
tested against real file layouts and the app was watched, but the **two cache
layouts are checked against directory trees written by hand** to match the
documented shape — `<output base>/external/<repo>` and `~/.conan2/p/b/<name><hash>/p`.
Both readers are built so a wrong guess costs a row its sources and nothing
else: the package still appears with its name, version and origin and simply
cannot be opened, which is a state the row already knows how to show.

## Estimate

2026-08-17 12:05 — done

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
- [x] Watched in the app, with a screenshot
- [x] Write down here what was ruled out on the way
- [x] `spec/project-view.md` says what Bazel and Conan projects show
- [x] A note's tooltip carries the whole sentence the pane cuts — found by
      looking at the WORKSPACE row in the app
- [ ] Teach `Subprojects` about Bazel and Conan, so a nested one has a row
      — **not done here**, and filed as 0527: `Subprojects.markers` also
      decides the scope pill, the language-server root, run configurations and
      the git tree, so two more markers is a change to all of those and wants
      its own item
