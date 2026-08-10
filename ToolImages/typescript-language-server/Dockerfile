# typescript-language-server, and the TypeScript it is a front end for.
#
# This is the image the editor starts when a project names it for
# `typescript-language-server`, and it is what the tool catalogue's contract
# describes: the server on the entry point, speaking the protocol on standard
# input and output, saying nothing before the first header, with the project
# mounted at /workspace.
#
# On the Node base image because the server is a Node program, and there is
# nothing under it to argue about — no compiler to match, only the runtime it
# is written for. The LTS line rather than current: this is somebody else's
# machine, and a language server is not the place to find out what changed in
# Node.
FROM node:22-bookworm-slim

# Two packages, and the second is not optional. typescript-language-server is a
# driver: the thing that actually answers about types is `tsserver.js`, out of
# the `typescript` package, and the server without it starts, answers the
# handshake with "Could not find a valid TypeScript installation", and exits.
#
# Pinned to 5, and that is not a preference. TypeScript 7 is the native
# compiler and ships no `tsserver.js` at all, so an image built with
# `typescript@latest` is the failure above with a newer version number on it —
# the same trap the install hint in `LanguageServers` was written for.
ARG SERVER_VERSION=5.3.0
ARG TYPESCRIPT_VERSION=5.9.3
RUN npm install --global --no-fund --no-audit \
	typescript-language-server@${SERVER_VERSION} \
	typescript@${TYPESCRIPT_VERSION} \
	&& npm cache clean --force

# What the project brings wins over what is in the image: the server looks for
# a `typescript` in the workspace's own `node_modules` before falling back to
# the global one, so a checkout that pins its compiler is compiled by the
# version it pins. That is the right way round and it is worth saying, because
# it means the version above is a floor rather than the answer — and it only
# holds if the project's dependencies have been installed, which happens on
# this machine and is visible through the mount.
WORKDIR /workspace

# `--stdio` is part of the entry point rather than something the caller adds,
# because this server chooses no transport for you: run with no flag it says so
# and exits. The editor passes nothing to an image — the arguments it would add
# for an installed copy are paths on this machine — so a transport the image
# does not name is a server that never speaks. It is also the one place a
# wrapper script would be tempting, and a wrapper is the one thing that breaks
# the contract: anything it printed would arrive where the first header should
# be.
ENTRYPOINT ["typescript-language-server", "--stdio"]
