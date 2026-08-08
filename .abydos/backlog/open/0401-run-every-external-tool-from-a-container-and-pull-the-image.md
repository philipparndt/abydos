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

*A known-good image, published.* The catalogue still lists none for any
language server, and that is still right — the list means somebody has run the
thing — but now something has. `ToolImages/gopls/Dockerfile` is what ran; what
is missing is pushing it somewhere anybody can pull from and listing that name.
The dev pod already publishes multi-architecture images from its own Makefile,
but not this way: its images are two static binaries and are assembled without
a builder, while gopls needs the Go toolchain beside it and so has a base image
under it. `make tool-image-gopls` builds it; publishing is the next step, and
then the other five.

*One page per language — done.* `SettingsSections.Section` carries children,
Tools has one per tool, and the sidebar indents them. The ⌘, window stopped
being an `NSTabViewController` — which cannot show a page under a page at all —
and hosts the same `SettingsPage` the editor does, so there is one navigation
over one list rather than two.

*Apple's runtime is preferred, and cannot see a docker image.* `discover`
prefers `container` because it needs no daemon. An image built locally with
docker is invisible to it, so a project naming one gets "there is no image
called…" and a pull attempt for something that is already here. Either say so
in that message, or look for the image in whichever runtime has it.

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
