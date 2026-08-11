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

## What the mechanism came to, and where it lives

**A server names what it reads; `ContainerPaths` maps it; everything else is
still refused.** Three pieces, and none of them is a new concept:

- `LanguageServerDefinition.outside` — a list, in the table, of directories the
  server reads that are not in the project. Each says where it is under this
  machine's home directory, where the image has to see it, and whether it is
  read-only. Empty for every server but kmp-lsp.
- `LanguageServers.mounts(outsideTheProjectFor:home:)` turns those into mounts
  for the ones this machine actually has, and `resolve` puts them on the
  container beside the project. `home` is a parameter so the whole thing is
  provable against a fixture rather than against whatever is in the person's
  own `~/.m2`.
- `ContainerPaths` gained `beyond` — the same mapping it already does for the
  project, over a short list. A path in none of them is refused exactly as
  before, which is the sentence this type exists to keep true.

`ToolContainer.mounts` was already a list emitting `-v` per mount, as the item
said, so nothing there changed at all.

**Three mounts for kmp-lsp and not two.** The item names `~/.m2/repository` and
`~/.gradle/caches`, and both are needed. The third is the one that is easy to
miss and that would have made the feature look finished while opening nothing:
go-to-definition into a library is answered by *unpacking one entry of the
`-sources.jar` to disk* and returning a `file:` URI for it, because that is what
an editor can open. Unpacked inside the container, that URI names a file this
machine does not have. So `~/.cache/kmp-lsp` is mounted too, and it is the one
that is writable.

### The three things the item asked to decide

**Read-only: yes, and narrower than asked.** What is mounted is
`~/.m2/repository` and `~/.gradle/caches`, not `~/.m2` and `~/.gradle` — the
directories above them hold `settings.xml` and `gradle.properties`, which is
where people keep registry passwords and signing keys. A language server has no
reason to see either, and `:ro` on top of that costs nothing to say. The
exception is the server's own scratch directory, which is writable because the
whole reason it is mounted is that this side has to read what lands in it.

**Whose mounts: this server's, from a table, one line per server — and this is
the view that was asked for.** A general rule would have to be "mount the
well-known cache for every language", and the three candidates differ in kind
rather than in detail:

- **kmp-lsp**: the directory *is* the answer. No classpath, no build tool; a
  dependency's source is only there. Without it, `null` at every boundary.
- **gopls**: `ToolImages/gopls/Dockerfile` carries a module cache inside the
  image, and an empty one costs a download rather than an answer. A saving,
  not a correctness fix, and the recipe already says so.
- **jdtls**: builds its classpath by *running* Maven and Gradle, which fetch
  what they are missing. Handing it a read-only `~/.m2` would break the thing
  it does rather than help it — the general rule would actively hurt here.

So a general answer really would have been guessed rather than driven, which is
the case the item warned about. The mechanism is general; the facts are per
server; a line is added when somebody has driven it. Adding `~/go/pkg/mod` to
gopls later is one line and no new machinery.

**A directory that is not there: read-only ones are left out, writable ones are
created.** A machine with no `~/.m2` is ordinary. A bind mount of a missing path
is a runtime error on Apple's runtime, and on docker it conjures a root-owned
empty directory into somebody's home folder — neither is a thing to do to a
machine because an editor opened a file. Left out, the server truthfully reports
no jars. The writable one is created because it is not somebody's cache: it is
the server's scratch, and leaving it out puts the answer somewhere unreadable
from here.

## Does it answer 0434 too? Half of it, and the half that was named

0434 left "two mounts, not one" for OpenSCAD: the project, because a `.scad` may
`include <…>` a file from anywhere in it, and the scratch directory the renderer
writes into, which is outside the project — and it said `ContainerPaths`
"answers for one of the two and the second needs its own".

**That is exactly what `ContainerPaths.beyond` is, and it is built and driven.**
An `OpenSCADCommand` that runs a container constructs `ContainerPaths` with the
scratch directory as the one thing beyond the project, translates every absolute
path in the arguments through it, and gets 0434's third question answered for
free: a path outside both is still nil, still refused, still not guessed at.

What it does **not** give 0434 is the declaring half. `outside` hangs off a
language server definition, and a renderer is not one; more to the point,
OpenSCAD's scratch directory is different per call, so there is nothing to write
in a table — the caller makes the mapping at the moment it makes the directory.
The per-call working directory 0434 warns about is likewise still 0434's.

A note saying so has been added to 0434's entry, above its unticked steps.

## Ruled out, and what was found on the way

**`cargo install --git … --rev …`, which is how the recipe should have read.**
The repository carries a `mason-registry` gitlink with no URL in `.gitmodules`,
and cargo updates every submodule before it will build: `no URL configured for
submodule 'mason-registry'`, and no flag turns it off. A depth-one `git fetch`
of the single commit ignores submodules and pins harder — one object, named by
its hash.

**Leaving the sidecar out, which looked obviously right.** `kmp-jar-indexer`
reads compiled `.class` files, and this recipe wants *source* jars, so the first
draft did not carry it. `spawn_jar_indexing` returns immediately when no sidecar
is present, so the sources half — pure tree-sitter, needing no sidecar at all —
never runs either. This is 0450's own finding arrived at from the other end, and
in a container it is worse than on a host: there is no `~/.cargo/bin` for it to
be found in later. The image carries it, downloaded from upstream's release with
a checked SHA-256 per architecture, because building it means a Gradle build, a
JDK and a native-image toolchain for a binary its own project publishes.

**Publishing the image.** Deliberately not, and not only because nothing here
should be pushed: what this builds is somebody else's server with a patch in it,
and putting that on a registry under this project's name is a claim nobody asked
us to make. The recipe is a file a person can read and check.

**The fork, and what happens to it.** Temporary by intent — the entry the item
asked for: `philipparndt/kmp-lsp` at `fa84a68` is v0.25.0 plus 0450's one
commit, 0450 is waiting for weeks of real use before the pull request, and **if
upstream takes it this recipe goes back to `Hessesian/kmp-lsp` at a release
tag**. That is written at the top of the Dockerfile itself, where somebody
changing it will see it, rather than only here.

**A single-module Maven project does not work, and it is the server's fault.**
Found by writing the fixture the obvious way — `pom.xml` beside `src/main/java`
— and watching a correctly mounted repository produce nothing for two minutes.
With no `workspace.json`, kmp-lsp probes `<root>/src/*/java` and classifies
everything under what it finds as *library* source; the workspace then has no
Kotlin/Java sources of its own, and `workspace_has_jvm_sources` keeps the whole
dependency pipeline shut. The one line that says so is `jar: no Kotlin/Java
sources in the workspace`. A reactor — a root that is only a pom, modules
underneath — has no `src` at its root, so nothing is probed and the pipeline
runs. That is the shape 0450 measured against, which is why it never saw this.
**It is worth an upstream issue and it is not this item's to fix**, but anybody
whose Maven project is one module and who sees no dependencies has just found
the reason.

## What it cost, measured on 2026-08-11

| | |
|---|---|
| the build, cold | 164 s, of which 162 is `cargo install` |
| the image | 132 MB — 16 MB of server, 19 MB of sidecar, Debian slim under it |
| a rebuild with the layer cache warm | under a second |
| container start to go-to-definition answered | about a second, on a two-file project |
| the live test, image already built | 1.1 s |

## Steps

- [x] Read 0434's "two mounts, not one" note, and answer both items with one
      mechanism
- [x] A language server can say it needs directories outside the project, and
      they are mounted read-only
- [x] `ContainerPaths` maps them, or says clearly why it does not have to
- [x] `ToolImages/kmp-lsp/Dockerfile`, pinned to a commit of the fork, with the
      reason for the fork written in the file
- [x] Driven end to end: a Java project in a container, go-to-definition into a
      `~/.m2` dependency, which is the exact thing 0450 measured going from
      `null` to a file and a line
- [x] Write down here what was ruled out on the way
- [x] `spec/tool-images.md` says what the project now does
