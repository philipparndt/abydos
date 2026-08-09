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

## Half of it is done, 2026-08-09

**`DevContainerFile.relative()` puts both sides through `realpath`**, which is
the "canonicalise both, and say which in a comment" above, and the comment says
it. `findsItsOwnFilesThroughASymlinkedRoot` is the test: a project reached
through a symlink, two devcontainers in it, and a `build.dockerfile` that has to
land beside the file naming it rather than at the top of the project.

It was fixed here rather than on its own because it stopped being latent.
Offering a project's several devcontainers in a menu (0424) needs each of them to
be a *different file*, and under `/tmp` they were not: both collapsed to
`devcontainer.json`, so both menu entries pointed at the same reconstructed path,
and the second container was never started — the first was handed out twice. The
afternoon this entry says it would waste, it wasted.

**`ContainerPaths` is the half still open**, and it is the half this entry was
right to be suspicious of. `toContainer(path:)` and `toHost(path:)` compare a
raw path against `host` with `hasPrefix`, so a symlinked root there would refuse
a file that is inside the project. It is latent rather than live today: both
callers that construct one — `LanguageServers` and `DevContainerFile` itself —
already hand it a canonical host. What it wants is not a `realpath` per call,
because that is a syscall on the path every `file:` URI in every LSP message
takes; canonicalising `host` once in `init`, or falling back to a canonical
comparison only when the plain one fails, are the two shapes worth choosing
between.

---

Its number is where it sits in the queue, not what it is worth doing next.
