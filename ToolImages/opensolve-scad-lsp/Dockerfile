# opensolve-scad-lsp, the OpenSCAD language server of opensolve-scad.
#
# The recipe rather than the result, like `ToolImages/openscad-lsp/Dockerfile`
# beside it: nothing publishes this, and the machine that wants it builds it the
# first time somebody opens a `.scad` in a project that asks for it. The image
# is named after this file, so editing it is what causes a rebuild and leaving
# it alone is what stops one.
#
# Two stages, for openscad-lsp's reason: the server is one binary that needs
# nothing at run time — BOSL2 and the fonts are inside it, and it never starts
# OpenSCAD, which it does not need — so the toolchain that makes it is left
# behind. What it needs to be *made* is more than openscad-lsp: its booleans
# are Manifold's, which `opensolve-manifold` compiles from source with the C++
# compiler this image has, downloading Manifold's and oneTBB's release tarballs
# and checking them against the SHA-256 that crate pins.
FROM rust:1.97-bookworm AS build

# A tag, not a branch, so two people get the same server whatever day they
# first opened a model. Moving this is a commit in this repository.
ARG OPENSOLVE_SCAD_TAG=v0.1.3
# `--locked` so the repository's own Cargo.lock decides the dependencies.
RUN cargo install --git https://github.com/cadscribe/opensolve-scad \
	--tag ${OPENSOLVE_SCAD_TAG} --locked --root /out opensolve-scad-lsp

FROM debian:bookworm-slim
COPY --from=build /out/bin/opensolve-scad-lsp /usr/local/bin/opensolve-scad-lsp

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# It speaks over standard input and output without being asked to.
ENTRYPOINT ["opensolve-scad-lsp"]
