# pyright, and a Python for it to ask about the project's imports.
#
# This is the image the editor starts when a project names it for `pyright`,
# and it is what the tool catalogue's contract describes: the server on the
# entry point, speaking the protocol on standard input and output, saying
# nothing before the first header, with the project mounted at /workspace.
#
# On the Node base image and not the Python one, which is the way round nobody
# guesses. pyright is a TypeScript program: Node is what it *runs* on and is
# not optional, while Python is what it *reads* and can be missing — a pyright
# with no interpreter still type-checks against the bundled typeshed and simply
# resolves no third-party import. So Node is the base and Python is installed
# on top, rather than the other way about.
FROM node:22-bookworm-slim

# The interpreter, because "resolves no third-party import" is most of what a
# real project is. pyright asks the interpreter where its site-packages are, and
# without one every `import requests` is an unresolved import — a wall of red in
# a project that builds, which reads as the editor being wrong about the code.
#
# It is still only half an answer, and the half that is missing is worth being
# plain about: the packages a project depends on are installed in a virtual
# environment on this machine, and this container cannot see one unless it is
# inside the project directory that is mounted. A project whose environment
# lives elsewhere gets the interpreter's own site-packages, which are empty.
RUN apt-get update \
	&& apt-get install --yes --no-install-recommends python3 python3-venv \
	&& rm -rf /var/lib/apt/lists/*

# Pinned, like the toolchain in the gopls image: the version is a decision about
# which answers a project gets, and this is the place to say which one. pyright
# tightens its inference in most releases, so the version is the difference
# between a diagnostic and no diagnostic rather than a detail.
ARG PYRIGHT_VERSION=1.1.411
RUN npm install --global --no-fund --no-audit pyright@${PYRIGHT_VERSION} \
	&& npm cache clean --force

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# `pyright-langserver --stdio`, which is the server; plain `pyright` is the
# command-line checker and would print a report where the first header should
# be. Both flags are in the entry point because the editor passes an image no
# arguments at all.
ENTRYPOINT ["pyright-langserver", "--stdio"]
