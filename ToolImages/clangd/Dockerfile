# clangd, and the headers a translation unit is nothing without.
#
# This is the image the editor starts when a project names it for `clangd`, and
# it is what the tool catalogue's contract describes: the server on the entry
# point, speaking the protocol on standard input and output, saying nothing
# before the first header, with the project mounted at /workspace.
#
# On Debian trixie rather than on bookworm, which is what the gopls image sits
# on, and the difference is the whole point of the image: bookworm's clangd is
# 14 and trixie's is 19, and for this tool the version *is* the feature — five
# years of diagnostics, of standard-library support and of how much it can say
# about a header it was not given a command for.
FROM debian:trixie-slim

# clangd-19 by name rather than the `clangd` metapackage, so which one this is
# is a decision written down here instead of whatever the distribution moves to
# next. The symlink is what the metapackage would have set up through
# alternatives, and the entry point below needs the plain name.
#
# libstdc++-14-dev is not a nicety. clangd is a compiler front end and a
# compiler front end with no standard library is a server that reports every
# `#include <string>` as a file that does not exist — the wall of red that
# reads as the editor being broken. It brings libc6-dev with it, and clang
# finds the GCC installation it belongs to the same way it does on any Debian.
ARG CLANG_VERSION=19
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends \
		clangd-${CLANG_VERSION} libstdc++-14-dev \
	&& ln --symbolic /usr/bin/clangd-${CLANG_VERSION} /usr/bin/clangd \
	&& rm -rf /var/lib/apt/lists/*

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
#
# What clangd wants to find here is a `compile_commands.json`, and what it does
# without one is guess: a lone `.c` gets a plausible command line and answers
# about itself, and anything that needs a project's include paths or its `-D`
# flags does not. That is true of clangd on any machine and is not something an
# image can fix — but it is the thing somebody notices first, so it is written
# here as well as in the catalogue.
WORKDIR /workspace

# No arguments: clangd with none is the language server on standard input and
# output. A wrapper script here would be the one thing that breaks the contract
# — anything it printed would arrive where the first header should be.
ENTRYPOINT ["clangd"]
