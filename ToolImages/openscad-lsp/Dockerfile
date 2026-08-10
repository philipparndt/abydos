# openscad-lsp, the language server for OpenSCAD.
#
# This is the recipe rather than the result: nothing publishes it, and the
# machine that wants it builds it the first time somebody opens a `.scad` in a
# project that asks for it. The image is named after this file, so editing it
# is what causes a rebuild and leaving it alone is what stops one.
#
# The reason this tool is the first one built here rather than pulled is its
# install hint: `cargo install openscad-lsp` means a Rust toolchain on the
# machine to get one binary, which is a large thing to ask for a hover. Almost
# nobody has it, so a server that answers is evidence the container path works
# rather than the host's copy replying.

# Two stages, and the contrast with `ToolImages/gopls/Dockerfile` is the point
# of having a second one at all. gopls cannot be separated from its toolchain:
# it shells out to `go list` and an image without `go` beside it starts, shakes
# hands and then knows nothing. openscad-lsp is the opposite — it parses with a
# vendored tree-sitter grammar, keeps its builtins inside itself, and never
# invokes the OpenSCAD binary — so the compiler is needed to make it and by
# nothing afterwards. Copying the one binary out turns 1.5 GB of Rust toolchain
# into about 100 MB of Debian, and "a Dockerfile per tool" survives the second
# tool being built a completely different way.
FROM rust:1.97-bookworm AS build

# Pinned, like gopls above it. A recipe that says `cargo install openscad-lsp`
# and nothing else gives two people different servers depending on the day they
# first opened a model, which is the failure that makes a build-here image worse
# than a published one rather than better. The cost is honest and stated in
# 0434: moving this number is a commit in this repository.
ARG OPENSCAD_LSP_VERSION=2.0.2
# `--locked` so the crate's own Cargo.lock decides its dependencies. Without it
# cargo resolves them afresh, and a build from an unchanged Dockerfile — which
# this app will not rebuild, because the recipe has not changed — quietly picks
# up whatever a transitive dependency published this morning.
RUN cargo install openscad-lsp --version ${OPENSCAD_LSP_VERSION} --locked --root /out

FROM debian:bookworm-slim
COPY --from=build /out/bin/openscad-lsp /usr/local/bin/openscad-lsp

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# `--stdio` on the entry point rather than left to the caller. A server started
# from an image is given no arguments — the contract in `ToolImageCatalogue`
# says the entry point is the whole command line, because anything this side
# added would arrive after the image's own flags — and openscad-lsp without
# `--stdio` listens on 127.0.0.1:3245 for a client that never comes. That is
# not a crash: the container sits there, the editor waits for a handshake, and
# the pane is empty for ever.
ENTRYPOINT ["openscad-lsp", "--stdio"]
