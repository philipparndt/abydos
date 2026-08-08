# 390. Run every external tool from a container, and pull the image

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
offering the installed copy or a custom image. None claims a known-good image
— the point of that list is that somebody has run the thing, and nobody has.

**What is left: the launch.** `LSPClient.start` takes an executable and
arguments, so handing it `ToolContainer.invocation(using:arguments:)` with
`ContainerPaths.mount` is small. The work is in the message path: every
`file:` URI going out mapped to the container's side and every one coming
back mapped home, in requests and notifications, including the ones nested
inside results — locations, edits, diagnostics.

Suggested next step: build one image for one server, gopls being the
smallest, prove the round trip, then list it in the catalogue as known-good
and repeat.

---

Numbered 53 while it was being worked on, which is what a
commit message citing it means.
