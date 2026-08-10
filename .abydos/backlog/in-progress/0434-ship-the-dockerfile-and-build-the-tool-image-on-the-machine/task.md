# 434. Ship the Dockerfile and build the tool image on the machine that uses it

0401 publishes an image per tool: build it, push it multi-arch, pull it back,
drive it against a real project, and only then write a line in
`ToolImageCatalogue`. That is the honest order and it works — `pharndt/abydos-gopls:dev`
went through all of it — but it is a standing commitment. Six servers means six
repositories, six Dockerfiles, six version tags to move when upstream moves, and
a registry account that has to stay alive for the app to keep working. The
moving `:dev` tag already had to be labelled as moving, because a list of images
known to work is a claim with a date on it.

The alternative is to ship the *recipe* rather than the *result*. Abydos carries
a Dockerfile per tool, and the first time somebody uses that tool in a container
it is built on their machine. Nothing is published, nothing is pulled from a
repository this project owns, and the maintenance is a text file rather than an
artefact.

## What it buys

No registry, no credentials, no `docker login`, and no
`Scripts/publish-tool-image.sh` preflight about builders and image stores. No
multi-arch build either: the machine builds for the architecture it is, which is
the only one it will ever run — and that removes the expensive half outright.
Measured while publishing gopls: 17 seconds for arm64 native against 110 for
amd64 under emulation, in the same build. A local build is the cheap side of
that number, always.

It also hands over responsibility, which is the point. A Dockerfile in the
repository is something a user can read, change, and pin themselves; a published
image is something they have to trust.

## What it costs, and what has to be answered

**The first use is a build, not a pull.** That is minutes rather than seconds,
and it happens at the moment somebody opened a file — the same manners problem
0433 is about, and probably the same answer.

**A build can fail where a pull cannot.** No network for the base image, a
`cargo install` that breaks against a new toolchain, a corporate proxy. The
sentence has to say which of those it was; `ContainerImages.isUnknownImage` and
the four-way pull failure are the shape to copy, not to reinvent.

**Two people get different images from one Dockerfile** as upstream moves,
unless what it installs is pinned. Since the point is not having to maintain
tags, the pinning has to be in the Dockerfile — and then updating it is a commit
here after all, which is worth being honest about rather than discovering later.

**Caching.** The built image needs a name and a way to know it is current — a
tag derived from the Dockerfile's own hash is the obvious route, so an edited
recipe rebuilds and an unedited one never does.

## The two can coexist, and probably should

The catalogue already offers a published image *or* a custom one per tool. A
third option — "build it here from the Dockerfile Abydos ships" — fits beside
them without displacing either, and lets the published route stay for the tools
where a build is genuinely expensive.

## Try it on OpenSCAD first

`openscad-lsp` is the right first case, and better than gopls was:

- Its install hint is `cargo install openscad-lsp`. Installing it on the host
  means installing a Rust toolchain to get one binary, which is exactly the
  situation containers exist for — and it is why almost nobody has it, so a
  hover that works is real evidence rather than the host's copy answering.
- It has no `rootMarkers`: any directory with a `.scad` in it is a project it
  can answer about, so there is nothing to arrange to test it.
- `ToolImages/gopls/Dockerfile` is the only one that exists; a second one, for
  a tool built a completely different way (cargo, not `go install`), is what
  says whether "a Dockerfile per tool" is a shape or a coincidence.

So: `ToolImages/openscad-lsp/Dockerfile`, built on the machine, named from the
Dockerfile's hash, driven end to end against a `.scad` file the way
`ContainerLSPLiveTests` drives gopls — a definition that opens the right file,
answered by a server that is not on this machine and cannot be.

## And OpenSCAD itself, which is the harder and more valuable half

The server is the easy case: it is one process speaking one protocol down a
pipe, and `LanguageServerLaunch` already knows how to put a container in front
of it. OpenSCAD *itself* — the renderer that turns a `.scad` into geometry — is
the one somebody actually cannot work without, and it is a hard dependency on an
installed copy today.

It is a hard dependency in **GoSTL**, not here. Abydos never invokes the binary:
`ModelPreview` deals in extensions and in finding `gostl`, and its only mention
of OpenSCAD is a comment saying a `.scad` is source. The dependency is one layer
down, in the viewer this project embeds:

- `GoSTL/OpenSCAD/OpenSCADRenderer.swift` — `findOpenSCADExecutable()` tries
  `/Applications/OpenSCAD.app/Contents/MacOS/OpenSCAD`, `/usr/local/bin/openscad`,
  `/opt/homebrew/bin/openscad` and `/usr/bin/openscad`, then `which openscad`,
  then throws `openSCADNotFound`.
- `GoSTL/UI/ErrorOverlay.swift` — the overlay that says "OpenSCAD Not Installed"
  and offers `brew install --cask openscad`.
- `GoSTL/App/AppState.swift` — a second hardcoded `/Applications/OpenSCAD.app`.

So this is a change in GoSTL first, then a tag, then a repin here — the route
0401's pin already established, and the reason `Package.swift` was moved to
GoSTL's root.

**What the change is.** `findOpenSCADExecutable() -> String` is the wrong shape,
because it answers with a *path* and the caller then builds a `Process` around
it — in a dozen places in that one file. What is needed is a seam that answers
with *how to run OpenSCAD*: a command and its arguments, which the host may
supply as a local binary or as `docker run --rm -v … abydos/openscad`. Injected
by the embedder rather than discovered, so a viewer used on its own keeps
exactly today's behaviour and finds the installed copy itself.

**The part that will bite is paths, and we already own the answer.** The
renderer writes temporary files into `workDir` and passes absolute paths to
OpenSCAD on the command line; inside a container none of those paths mean what
they say. `ContainerPaths` exists for precisely this — it translates between the
project on this machine and the mount inside, for paths and for `file:` URIs,
and refuses anything outside the project rather than guessing. The `.scad` being
rendered may also `include <…>` a file from anywhere in the project, so the
mount has to be the project rather than the one file, and the include path has
to survive the translation.

**Why it is worth the upstream change.** OpenSCAD is a 200 MB cask that somebody
has to install and keep current before a `.scad` file will preview at all, on a
machine that has already installed Abydos. Building it into an image once, from
a Dockerfile that says which version, is the whole argument for this item stated
in the one place where a user actually feels it — and unlike the language
servers, the difference is visible rather than inferred: the model appears, or
an overlay tells you to go and install something.

### The version is the argument, and today's advice is wrong

What is depended on is a **developer snapshot**, not a release. Measured on this
machine, all three at once:

| what | version |
|---|---|
| `brew install --cask openscad` — what the overlay tells people to run | **2021.01** |
| `brew install --cask openscad@snapshot` | 2026.06.12 |
| what is actually installed and working here | 2026.01.29 (git 6fcd5676) |

The stable release is five years old and not what this depends on. So the
sentence in `ErrorOverlay.swift` sends somebody to install the wrong OpenSCAD,
and it will fail in a way that looks like a bug in the model rather than a
too-old renderer. **That is worth fixing on its own, before and regardless of
any container work** — the overlay should name the snapshot cask, and ideally
say the minimum version it needs.

And it turns the earlier worry inside out. Above, pinning was written down as a
*cost*: pinning a Dockerfile's contents puts the maintenance back here after
all. For a nightly it is the opposite — there is no stable tag to sit still on,
so an unpinned instruction is not reproducible even in principle, and a
Dockerfile naming one snapshot is the only form this dependency can take
honestly. Nobody can reasonably be asked to track a dev snapshot by hand.

Two things to establish before writing the Dockerfile, because they decide what
it can say:

- **What a durable pin looks like.** `2026.01.29 (git 6fcd5676)` names both a
  date and a commit. Whether dated Linux snapshot artefacts stay downloadable
  once they are old is the question — if they are pruned, the commit is the only
  pin that keeps working and the image has to be built from source.
- **What building from source costs.** OpenSCAD pulls in CGAL, Qt and Manifold;
  this could be a long build rather than the couple of minutes gopls was. If it
  is, a dated artefact with a checked hash is the better trade, and the pin
  becomes "this snapshot, while it exists".

### One more thing containerising has to preserve

`OpenSCADRenderer` sets `process.currentDirectoryURL` to a *different* directory
per call — `runDir` when exporting, `workDir` for the colour passes, `sourceDir`
for the CSG ones — and the comments say why: relative `include <…>` and
`use <…>` resolve against it. Any container form has to reproduce the working
directory per call, not once for the image, or a model that includes a file
beside it renders on this machine and fails in the container. That is the sort
of difference that shows up as "it works for me".

*One thing noticed on the way past, unrelated to this item.*
`OpenSCADRenderer.findOpenSCADExecutable` reads its `which` output with
`readDataToEndOfFile()`, which is the exact deadlock `ProcessPipes` was written
to remove from this repository. It is safe there — `which` says one short line —
but the same file makes fifteen or so `Process` calls, and the ones running
OpenSCAD are the chatty kind. Worth a look while the file is open anyway.

## Steps

- [x] `ToolImages/openscad-lsp/Dockerfile`: a pinned `cargo install`, the server
      on the entry point speaking the protocol on standard input and output
- [x] An image name derived from the recipe, so an edited Dockerfile rebuilds
      and an unedited one never does
- [ ] The recipe is found both in the `.app` and in a checkout, and the
      Dockerfiles travel in the bundle
- [x] Build rather than pull when the name is one this app makes, with a
      sentence per way a build fails rather than the runtime's output
- [x] A third option beside the published image and the custom one: "build it
      here", offered only for a tool a Dockerfile ships for
- [x] `{"openscad-lsp": "build"}` in a project's `.abydos/tools.json` starts the
      built image
- [ ] Driven end to end against a `.scad`, the way `ContainerLSPLiveTests`
      drives gopls
- [ ] Establish what a durable pin for the OpenSCAD snapshot looks like, before
      writing a Dockerfile that claims one
- [ ] The seam in GoSTL: how to run OpenSCAD, injected by the embedder rather
      than discovered, with today's behaviour as the default
- [ ] Write down here what was ruled out on the way
- [ ] `spec/devcontainers.md` says what the project now does
