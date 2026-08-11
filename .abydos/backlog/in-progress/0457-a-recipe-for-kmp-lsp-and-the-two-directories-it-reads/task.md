# 457. A recipe for kmp-lsp, and the two directories it reads outside the project

`ToolImages/kmp-lsp/Dockerfile`, so somebody can use the fast Java server without
a Rust toolchain on their machine. 0434 built exactly this mechanism and
`ToolImages/openscad-lsp/Dockerfile` is the model — a cargo build in one stage,
one binary copied into a slim image, and the whole thing named from the
Dockerfile's own hash so editing the recipe is what causes a rebuild.

Today the only way to run it is `cargo install --path ~/dev/kmp-lsp`, which is
the same "install a whole toolchain to get one binary" that made openscad-lsp the
first case for building here rather than pulling.

## The wrinkle, and it is the whole item

**kmp-lsp reads two directories that are not in the project.** It finds compiled
and source JARs under `~/.gradle/caches`, and — since the fork — under
`~/.m2/repository`. A tool container is given the project and nothing else, and
`ContainerPaths` refuses anything outside it *by design*: "the container cannot
see it, and inventing a path inside would point the server at the wrong file."

So a containerised kmp-lsp without more mounts is a kmp-lsp that has lost exactly
what the fork was written to add. It would index the project's own source
perfectly — which 0450 measured as the half that matters most — and answer
`null` at every dependency boundary, which is the state the fork exists to end.

This is the same shape 0434 hit and deliberately left: OpenSCAD needs the project
*and* a scratch directory outside it, recorded there as "two mounts, not one".
Whoever takes this should read that note first; the two items want the same
answer and it should be built once.

**`ToolContainer.mounts` is already a list** and `-v` is emitted per mount, so
the container layer can carry it. What is missing is a language server saying it
needs more than the project, and `ContainerPaths` learning about a second
mapping without becoming a thing that maps anything anywhere.

## Which source to build from

Upstream has no Maven support, so the recipe has to build the user's fork —
`philipparndt/kmp-lsp`, branch `feat/maven-local-repository-jars`, commit
`fa84a68` — and it should pin the **commit**, not the branch, or the image's
hash stops meaning anything the moment the branch moves.

That is temporary by intent. 0450 is waiting for weeks of real use before the
pull request; if it is taken, this recipe should go back to upstream at a tag,
and the entry should say so rather than leaving a fork pinned in the repository
for ever. **Write down here which it is**, so nobody has to guess later whether
the fork is deliberate.

## Worth deciding

- **Read-only mounts.** A language server has no business writing to `~/.m2`, and
  `:ro` costs nothing to say.
- **Whether the mounts are kmp-lsp's or every server's.** gopls wants
  `~/go/pkg/mod` by the same argument, and jdtls a `~/.m2` of its own. A general
  answer is better than three special cases, and worse than one if it is guessed
  at rather than driven.
- **What happens when the directory is not there.** A machine with no `~/.m2` is
  ordinary, and a mount of a missing path is a runtime error rather than an empty
  directory.

## Steps

- [ ] Read 0434's "two mounts, not one" note, and answer both items with one
      mechanism
- [ ] A language server can say it needs directories outside the project, and
      they are mounted read-only
- [ ] `ContainerPaths` maps them, or says clearly why it does not have to
- [ ] `ToolImages/kmp-lsp/Dockerfile`, pinned to a commit of the fork, with the
      reason for the fork written in the file
- [ ] Driven end to end: a Java project in a container, go-to-definition into a
      `~/.m2` dependency, which is the exact thing 0450 measured going from
      `null` to a file and a line
- [ ] Write down here what was ruled out on the way
- [ ] `spec/tool-images.md` says what the project now does
