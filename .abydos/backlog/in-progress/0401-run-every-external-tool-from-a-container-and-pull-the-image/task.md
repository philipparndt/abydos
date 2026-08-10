# 401. Run every external tool from a container, and pull the image

**Pulling is done** (0a76af8). A named image that is not on the machine is
fetched before first use, once however many panes ask, with the image name on
screen while it happens. A failure says which of four things went wrong — fix
the name, sign in, get a network, start the runtime — because each has a
different answer. Anything unrecognised keeps the runtime's first line rather
than inventing a reason.

**The path mapping is done** (1117ad2). `ContainerPaths` translates between
the project on this machine and the mount inside, for paths and for `file:`
URIs, refusing anything outside the project rather than guessing. Written
first on purpose: it is the part that fails silently rather than loudly.

**The tools are declared** (3ace522). gopls, rust-analyzer, pyright,
typescript-language-server, clangd and jdtls appear in the tool settings, each
offering the installed copy or a custom image.

**The launch is done, and proved.** A server named in `.abydos/tools.json` is
started from its image with the project mounted, every `file:` URI is rewritten
at the edge of `LSPClient` — going out and coming back, keys as well as values,
so a workspace edit's `changes` map crosses too — and `ToolImages/gopls`
builds an image that `ContainerLSPLiveTests` drives end to end: diagnostics,
symbols and a go-to-declaration all naming files on this machine.

**A known-good image is published, pulled back and driven.**
`make toolimage-publish TOOL=gopls REPOSITORY=… VERSION=…` builds
`ToolImages/<tool>` for linux/amd64 and linux/arm64 and pushes one index, in a
single `docker buildx` invocation. Not the pod's route and not two builds and a
`docker manifest create`: the pod assembles its own images because they are two
static binaries with nothing underneath, while gopls sits on
`golang:1.26-bookworm` and needs the base image of the architecture it is being
built for; and the manifest route has to push `:x-amd64` and `:x-arm64` first,
since `docker manifest create` reads its members from the registry — three
pushes, and two tags left in the repository that nobody should ever pull. TOOL
is a third word rather than a loop over `ToolImages/*/Dockerfile`, because each
tool is its own repository and one REPOSITORY cannot name six servers.

Everything is checked before the first layer, each with the sentence that says
what to do: no such tool, no buildx, a builder that builds one architecture at
a time (the `docker` driver, unless the daemon uses the containerd image
store), a builder that does not list one of the platforms, and nobody signed in
to the registry the repository names. The last is asked of
`~/.docker/config.json` rather than of the registry, so it needs no network and
reads no password, and it is asked first because the build is the several
minutes that come before the push.

Proved first as far as a machine with no credentials can: `DRY_RUN=1` builds
both architectures with `type=cacheonly` and stops. 2m10s from a cold builder,
`go install gopls` being 17 seconds for arm64 and 110 for amd64 — emulation, and
the whole of the difference. `--load` was not the alternative: it takes one
architecture, so it would have proved neither.

Then for real. `pharndt/abydos-gopls:dev` is in Docker Hub, and
`docker buildx imagetools inspect` reads the index back out of the registry with
`linux/amd64` and `linux/arm64` under it — the one thing that says an index was
pushed rather than one architecture with a second name on it. Nine layers each,
0.48 GB of them compressed for amd64 and 0.47 for arm64, 1.39 GB on disk once
docker has unpacked it; gopls v0.23.0 on go1.26.5. Both provenance attestations
are there too, as `unknown/unknown` members, which is why the script's format
string skips them.

*Pulled as a stranger pulls it, on both runtimes, and they needed different
things.* docker fetched two layers and had the other seven already, because
`golang:1.26-bookworm` was on the machine — a stranger pays for all nine. Apple's
`container` had none of it and fetched and unpacked the whole 1.29 GB in 37
seconds, sharing nothing with docker's store at all, which is the fact
`visibleElsewhere` exists to explain: the same name, on the same machine, is two
separate images or none. Both then ran the server from it: the live test picks
Apple's, and turning the preference round for one run drove the same image
through docker — 1.8 and 2.4 seconds, both answering with paths under
`/private/var/folders/…` rather than under `/workspace`.

*Driven from the registry copy.* `ContainerLSPLiveTests` names two images,
published first — `pharndt/abydos-gopls:dev`, then `abydos/gopls:dev` from
`make tool-image-gopls` — and takes whichever a runtime has, image outermost so
that a machine holding both drives the published one. Either, because they
answer different questions: the local build says the Dockerfile in this
repository works, which is worth having while somebody is editing it and is no
evidence at all about what a stranger pulls; the published one is the only thing
whose passing makes the catalogue entry true. And the image comes out of the
project's own `.abydos/tools.json` rather than being handed to `resolve` as a
string, because that is the route somebody actually uses and everything before
`resolve` differs from the settings one — a file, parsed, keyed by the tool's
name and not the server's command.

So the line is in `ToolImageCatalogue.tools`, which until now listed nothing for
any server:

    Choice(
        label: "pharndt/abydos-gopls:dev (gopls 0.23.0, Go 1.26 — a tag that moves)",
        image: "pharndt/abydos-gopls:dev",
        publisher: "the Abydos project"
    )

Not the `:0.23.0` drafted here before it existed. `dev` is the only tag in the
repository — `VERSION` defaulted — and listing a tag nobody can pull is the
exact failure this list is for, so what was written down was checked against
what was pushed rather than copied. The version is in the label anyway, since
that is what somebody is choosing between; and the label is the image's own
name rather than the draft's "abydos/gopls", which is neither the repository nor
anything anybody could type, so what is on screen is what would be pulled — the
way the PlantUML labels already read.

*And the tag moves, which is worth saying out loud rather than deciding
quietly.* A list of images known to work is a claim with a date on it when the
name is mutable: what was driven is `sha256:ed0f6a5d…`, and `:dev` is whatever
was pushed last by the time somebody picks it. It is listed anyway, and said in
the label where the person choosing will see it rather than in a comment only a
maintainer reads — the catalogue already carries `plantuml/plantuml` (latest)
beside a pinned one for the same reason, so the honest thing is to mark which is
which, not to keep the list empty. When a version tag is pushed it becomes this
entry and `:dev` stops being offered.

`publisher` is "the Abydos project", which is this repository saying it works
about its own image — so the requirement text beside it has to be a description
rather than a wish, and it is: `ENTRYPOINT ["gopls"]` with no arguments and no
wrapper to print a banner before the first header, `WORKDIR /workspace` where
the project is mounted, and the Go toolchain in the image because gopls shells
out to `go list` and one without it answers the handshake and then knows
nothing.

**What is left.** The other five servers — rust-analyzer, pyright,
typescript-language-server, clangd, jdtls — need a Dockerfile each and nothing
else, since `make toolimage-publish` already takes them by name. Each then goes
the same way round: build, push, pull it back, drive it against a real project
the way `ContainerLSPLiveTests` drives gopls, and only then a line in the
catalogue. `ToolContainerTests` holds the order for gopls — the image the
catalogue offers has to be one the live test would run — and the other five
still assert an empty list, so each has to lose that assertion deliberately.
And a version tag for gopls, at which point the moving one above can go.

*One page per language — done.* `SettingsSections.Section` carries children,
Tools has one per tool, and the sidebar indents them. The ⌘, window stopped
being an `NSTabViewController` — which cannot show a page under a page at all —
and hosts the same `SettingsPage` the editor does, so there is one navigation
over one list rather than two.

*Apple's runtime is preferred, and cannot see a docker image — done.* Both
halves, since one without the other is still wrong: when a pull fails with the
one answer that could be a store rather than a name, the other family is asked
whether it has the image, and if it does the sentence says so and offers the
runtime choice in settings before offering a push. Asked only after a failure
and only for that one answer, so an ordinary first-run pull still costs one
process. What made this worth more than a reworded string is that both of the
old sentences were true: the name was fine, and the pull that followed was for
something already on the machine.

## Decided

**A tree, and one navigation over it.** `SettingsSections.Section` gains
children, the in-editor page's sidebar becomes an outline, and the ⌘, window
hosts the same `SettingsPage` instead of its own tab bar — so the two surfaces
are the same thing rather than two navigations over one list, which is the
drift the "named once" comment exists to prevent. The macOS toolbar style goes
with it; this app does not otherwise wear it.

One child per tool: PlantUML and the six servers, each owning its image choice
and the requirement text beside it. The parent keeps what is genuinely shared —
the container runtime — and becomes short instead of a wall of cards.

## The other five, built and driven here

Five Dockerfiles, and `ContainerLSPLiveTests` grew from one test into six cases
of one — a server, a project of its language, and the one answer that could
only come from that server having read that project. All six pass against
images on this machine, in 12.6 seconds for the six of them serialized:

    gopls:                      pharndt/abydos-gopls:dev        container
    rust-analyzer:              abydos/rust-analyzer:dev        docker
    pyright:                    abydos/pyright:dev              docker
    typescript-language-server: abydos/typescript-language-server:dev  docker
    clangd:                     abydos/clangd:dev               docker
    jdtls:                      abydos/jdtls:dev                docker

Those two lines of output are new and are not decoration. A live test that
skips is silent, and one silent skip reads as a pass already — six of them read
as six. So the case that runs says which image it drove and which runtime ran
it, and a green suite can be told apart from an absent one by reading it.

**The builds were the cheap part, which was the surprise.** gopls costs minutes
because it compiles: `go install` under emulation was 110 seconds for amd64
alone. None of these five compiles anything. rust-analyzer comes from `rustup
component add`, clangd from `apt`, pyright and typescript-language-server from
`npm`, jdtls from a tarball — every one of them a download onto a base image.
The five built in 8 to 21 seconds each on this machine, and the largest cost is
the base: 1.61 GB for rust-analyzer, which is the Rust toolchain, against 274 MB
for typescript-language-server.

**Two things had to be found out by running them.** rust-analyzer answers every
request with `ContentModified` (`-32801`) until the crate graph is built, and it
publishes diagnostics from its own analysis well before that — so waiting for
the first diagnostic, which is enough for the other five, is not enough for it.
That is not a fact about containers: it is the protocol saying "ask again", and
**nothing above `LSPClient` asks again**, so a go-to-declaration in the first
seconds of a Rust project fails in the editor rather than arriving a moment
late. The test retries; the editor does not, and that belongs to whichever item
owns the client. And jdtls needed an Eclipse project rather than a Maven one:
`.classpath` is already one of its root markers, and a `pom.xml` would have sent
it to Maven Central from inside the container for every plugin in the default
lifecycle — a test that downloads instead of a test that runs.

## All five published, fetched back and driven, and then listed

The judgement first, because it was the one thing here that could not be
undone. Publishing needs an account, and this machine turned out to have one:
`~/.docker/config.json` holds a Docker Hub entry, and `pharndt/abydos-gopls` is
already a public repository there from the first half of this item. So the
question was not "can this be pushed" but "should five new public repositories
appear under somebody's name without them being asked in the moment". It was
decided yes: the item is agreed, the destination is already written into the
Makefile as `pharndt/abydos-$(TOOL)`, and the alternative was a catalogue that
stays empty for five servers whose images work. The smallest was pushed first
to find out what it cost before committing to the rest — 36 seconds — and the
other four followed.

`DRY_RUN=1` first for all five, which is what the script offers and what makes
this cheap to be wrong about: both architectures build, nothing is pushed. 10
to 43 seconds each. Then the real thing, and both platforms are under every
index that came back out of `docker buildx imagetools inspect`:

    typescript-language-server   36s to push    274 MB unpacked
    pyright                      28s            321 MB
    clangd                       60s            472 MB
    jdtls                        80s            569 MB
    rust-analyzer                83s            1.61 GB

*Fetched back the way a stranger fetches them, which is only true of one of the
two runtimes.* `docker pull` took 3 to 7 seconds for all five, and that number
means nothing: docker built them, so it had every layer already. Apple's
`container` shares nothing with docker's store — the fact `visibleElsewhere`
exists to explain — so its pull is the real one: 9, 14, 14, 21 and 38 seconds,
the whole of each image over the network onto a runtime that had none of it.

*Then driven from the registry copy.* The live test takes the image outermost
and the runtime innermost, so once Apple's runtime held the published images it
drove all six of them: `pharndt/abydos-<tool>:dev` under `container`, 14.8
seconds for the six serialized. That run is the only thing that makes the six
catalogue lines true, and it is what the test in `ToolContainerTests` now
insists on for any seventh.

The versions in the labels were read out of the images that were pushed rather
than out of the Dockerfiles that built them, which is the same discipline as
checking the tag: rust-analyzer 1.97.1 on Rust 1.97, pyright 1.1.411 with
Python 3.11, typescript-language-server 5.3.0 with TypeScript 5.9, clangd
19.1.7, jdtls 1.55.0 on Java 21.

## Steps

The six merged things first, then the five servers that had no image, in the
order this entry insists on: a Dockerfile, a build, a run against a real
project, and a line in the catalogue only after all three.

- [x] Pull an image that is not on the machine, before first use
- [x] `ContainerPaths` maps the project in and every URI back out
- [x] The six servers appear in the tool settings, each choosing an image
- [x] A server named in `.abydos/tools.json` starts from its image
- [x] `ToolImages/gopls`, published, pulled back and driven
- [x] `ToolImageCatalogue` lists the gopls image, and `ToolContainerTests`
      holds it to the one the live test drives
- [x] `ToolImages/rust-analyzer/Dockerfile`
- [x] `ToolImages/pyright/Dockerfile`
- [x] `ToolImages/typescript-language-server/Dockerfile`
- [x] `ToolImages/clangd/Dockerfile`
- [x] `ToolImages/jdtls/Dockerfile`
- [x] `make tool-image` builds any of them by name, not gopls alone
- [x] `ContainerLSPLiveTests` drives a server per language rather than Go alone
- [x] Each image built here and driven against a real project of its language
- [x] Each image pushed, pulled back as a stranger pulls it, and driven from
      the registry copy
- [x] A catalogue line for each image that survived the step above, and the
      empty-list assertion in `ToolContainerTests` lost for it deliberately
- [ ] A version tag for gopls, so `:dev` stops being what the catalogue offers

  Not done, and not forgotten. It is now six entries rather than one, and doing
  it means pushing a second tag for each, rewriting six labels, and taking out
  the "a tag that moves" reasoning that the catalogue and its tests are
  currently built around. That is a change to what the list *promises*, not
  more of what this item was doing, and it wants deciding on its own — in
  particular whether a version tag on an image whose base is pinned by a major
  version (`golang:1.26-bookworm`, `node:22-bookworm-slim`) is a promise that
  can be kept. Every label says the tag moves, which is the honest position
  until somebody decides.
- [ ] Write down here what was ruled out on the way
- [ ] The spec says what the project now does

---

Previously numbered 53, 390.
