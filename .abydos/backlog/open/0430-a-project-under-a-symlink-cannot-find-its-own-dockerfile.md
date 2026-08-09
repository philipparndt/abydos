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

---

Its number is where it sits in the queue, not what it is worth doing next.
