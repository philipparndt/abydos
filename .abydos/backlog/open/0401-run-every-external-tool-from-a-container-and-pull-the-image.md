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

**What is left.**

*A known-good image, published — the goal exists, the push has not happened.*
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

Proved as far as a machine with no credentials can: `DRY_RUN=1` builds both
architectures with `type=cacheonly` and stops. 2m10s from a cold builder,
`go install gopls` being 17 seconds for arm64 and 110 for amd64 — emulation, and
the whole of the difference. `--load` was not the alternative: it takes one
architecture, so it would have proved neither. Unproven is everything past that
point — the upload, the index that appears in the registry, and the
`imagetools inspect` that is meant to read back its two platforms.

What is left, in order. Somebody with a Docker Hub or ghcr login runs
`make toolimage-publish TOOL=gopls VERSION=0.23.0`. The result is pulled on
both architectures and driven by `ContainerLSPLiveTests`. Only then does the
line go into `ToolImageCatalogue.tools`, which lists nothing for any server on
purpose:

    Choice(
        label: "abydos/gopls (gopls 0.23.0, Go 1.26)",
        image: "pharndt/abydos-gopls:0.23.0",
        publisher: "the Abydos project"
    )

It is written here rather than commented out in the catalogue: a commented-out
entry in a list whose whole point is that somebody has run the thing is an
invitation to uncomment it without running it. Then the other five, which need
a Dockerfile each and nothing else — the goal already takes them by name.

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

---

Previously numbered 53, 390.
