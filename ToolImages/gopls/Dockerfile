# gopls, and the Go toolchain it is a front end for.
#
# This is the image the editor starts when a project names it for `gopls`, and
# it is what the tool catalogue's contract describes: the server on the entry
# point, speaking the protocol on standard input and output, saying nothing
# before the first header, with the project mounted at /workspace.
#
# On the Go base image rather than a slim one with a binary copied in: gopls is
# not self-contained. It runs `go list` to work out what a package is, and a
# gopls with no `go` beside it starts, answers the handshake, and then knows
# nothing about any symbol — the failure that reads as "the editor is broken"
# rather than as "the image is missing a toolchain".
FROM golang:1.26-bookworm

# Pinned, like the debugger in the pod image: the version is a decision about
# which answers a project gets, and this is the place to say which one.
ARG GOPLS_VERSION=v0.23.0
RUN go install golang.org/x/tools/gopls@${GOPLS_VERSION}

# The module cache lives in the image, so a project that has already been
# indexed once does not fetch the world again on the next container. It is a
# cache and not state: an empty one costs time and nothing else.
ENV GOFLAGS=-mod=mod
ENV GOPATH=/go
ENV GOMODCACHE=/go/pkg/mod

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# No arguments: gopls with no subcommand is the language server on standard
# input and output, which is exactly what is wanted. A wrapper script here
# would be the one thing that breaks the contract — anything it printed would
# arrive where the first header should be.
ENTRYPOINT ["gopls"]
