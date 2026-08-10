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
