# 513. The dependencies section cannot read Bazel or Conan

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

## Steps

- [ ] Decide whether this section may run a build tool, and write the answer
      down — it is the decision both kinds need and neither can start without
- [ ] Read a Bazel workspace's externals, or say exactly why a build is needed
      first
- [ ] Read a Conan project's packages, or say exactly why the recipe has to run
- [ ] Watched in the app, with a screenshot
- [ ] Write down here what was ruled out on the way
- [ ] `spec/editor.md` says what Bazel and Conan projects show
