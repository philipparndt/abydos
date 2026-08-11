# kmp-lsp, the second opinion about Java: tree-sitter and no JVM.
#
# The recipe rather than the result, like `ToolImages/openscad-lsp/Dockerfile`
# beside it: nothing publishes this, and the machine that wants it builds it the
# first time somebody opens a Java file in a project that asks for it. The image
# is named after everything in this directory, so editing this file is what
# causes a rebuild and leaving it alone is what stops one.
#
# Why it is worth having at all is 0450's measurement: on Eclipse's
# `eclipse.platform.ui` — 143 bundles, 7,566 Java files — this had the whole
# project indexed at 2.6 seconds and answered go-to-definition across bundles,
# while jdtls on the same file and the same position was still silent at ten
# minutes holding 3.97 GB. Its install hint is `cargo install kmp-lsp`, which is
# a Rust toolchain on the machine to get one binary, and that is the situation
# this whole route exists for.

# ── Which source this builds, and why it is not upstream ─────────────────────
#
# **This builds a fork, deliberately, and it should not stay one.**
# `philipparndt/kmp-lsp` on `feat/maven-local-repository-jars` adds one commit
# to upstream v0.25.0: the JAR pipeline learns to look in `~/.m2/repository`
# beside `~/.gradle/caches`. Upstream has no Maven support at all, so on a
# pom-first project the unforked server answers `null` at every dependency — the
# state 0450 measured before the change and `TelegramBot.java:32` after it.
#
# 0450 is in `waiting/` for weeks of real use on a five-hundred-bundle Tycho
# product before the pull request is offered. **If upstream takes it, this
# recipe should go back to `Hessesian/kmp-lsp` at a release tag and the fork
# should disappear from this repository.** That is the whole reason this
# paragraph is here: a pinned fork with no note beside it is indistinguishable
# from an accident a year later.
#
# The commit and not the branch. A branch is a name that moves, and the image is
# named after this file — so a recipe pinning a branch would keep its
# fingerprint, never rebuild, and quietly mean something different from what it
# said on the day it was written.
FROM rust:1.97-bookworm AS build
ARG KMP_LSP_REPOSITORY=https://github.com/philipparndt/kmp-lsp
ARG KMP_LSP_COMMIT=fa84a68ea364e80db822260c2137da19a0f48e96
# Cloned by hand rather than with `cargo install --git … --rev …`, which is what
# this said first and which does not work here: the repository carries a
# `mason-registry` gitlink with no URL in `.gitmodules`, and cargo insists on
# updating every submodule before it will build — `no URL configured for
# submodule 'mason-registry'`, and no flag turns it off. `git fetch` of one
# commit does not care about submodules at all, and it pins harder than cargo's
# `--rev` did: one object, named by its hash, and nothing else in the history.
#
# `--locked` so the checkout's own Cargo.lock decides the dependencies. Without
# it cargo resolves them afresh, and a build from an unchanged Dockerfile — which
# this app will not rebuild, because the recipe has not changed — quietly picks
# up whatever a transitive dependency published this morning.
RUN set -eu; \
	git init --quiet /src; \
	git -C /src remote add origin ${KMP_LSP_REPOSITORY}; \
	git -C /src fetch --quiet --depth 1 origin ${KMP_LSP_COMMIT}; \
	git -C /src checkout --quiet FETCH_HEAD; \
	cargo install --path /src --locked --root /out

# ── The sidecar, which is not optional however much it looks it ──────────────
#
# `kmp-jar-indexer` reads compiled `.class` files out of jars, and the obvious
# reading is that a server which only wants *source* jars does not need it. That
# is wrong, and it cost 0450 an afternoon: `spawn_jar_indexing` returns
# immediately when no sidecar is present, so the sources-JAR half — pure
# tree-sitter, needing no sidecar at all — never runs either. **Without this
# binary beside `kmp-lsp` the image indexes the project perfectly and knows
# nothing about any dependency**, which is exactly the failure the mounts below
# exist to prevent, arrived at by a different road.
#
# Downloaded rather than built. It is a GraalVM native image of a Kotlin
# program, and building it here would mean a Gradle build, a JDK and a
# native-image toolchain in this recipe for a binary its own project publishes.
# Pinned to a release tag with a checked SHA-256 for each architecture, so this
# is as reproducible as the cargo build above it.
#
# From *upstream's* release rather than the fork's: the fork changes where jars
# are looked for, which is `kmp-lsp`'s half of the pipeline, and the protocol
# between the two is a line of JSON per jar. v0.25.0 is the release the forked
# commit sits on top of.
FROM debian:bookworm-slim AS sidecar
ARG KMP_LSP_VERSION=v0.25.0
ARG SIDECAR_SHA256_AARCH64=bb0a885400359a715fd1428c3c01850249eab8493d9ebe491cbfbe855c55ae3b
ARG SIDECAR_SHA256_X86_64=6b9d410769f030b941a1cc7fab57154862823f9554f655e30bc18e5317773203
RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl \
	&& rm -rf /var/lib/apt/lists/*
# `dpkg --print-architecture` rather than the `TARGETARCH` build argument: that
# one is BuildKit's, and this recipe is also built by Apple's `container`, where
# an unset variable would silently make the name `kmp-jar-indexer-linux-.gz`.
RUN set -eu; \
	case "$(dpkg --print-architecture)" in \
		arm64) arch=aarch64; sha=${SIDECAR_SHA256_AARCH64} ;; \
		amd64) arch=x86_64;  sha=${SIDECAR_SHA256_X86_64} ;; \
		*) echo "kmp-jar-indexer is not published for $(dpkg --print-architecture)" >&2; exit 1 ;; \
	esac; \
	curl -fsSL -o /tmp/sidecar.gz \
		"https://github.com/Hessesian/kmp-lsp/releases/download/${KMP_LSP_VERSION}/kmp-jar-indexer-linux-${arch}.gz"; \
	echo "${sha}  /tmp/sidecar.gz" | sha256sum -c -; \
	gunzip -c /tmp/sidecar.gz > /out-sidecar; \
	chmod 0755 /out-sidecar

FROM debian:bookworm-slim
# Beside each other, because that is how the server looks for the sidecar: the
# directory of the running executable first, `~/.cargo/bin` second. Anywhere
# else on the PATH is not somewhere it looks.
COPY --from=build /out/bin/kmp-lsp /usr/local/bin/kmp-lsp
COPY --from=sidecar /out-sidecar /usr/local/bin/kmp-jar-indexer

# ── The three directories this image is given from outside ───────────────────
#
# The mounts themselves are Abydos's — `LanguageServers.known` names them, one
# line each, and refuses to invent any others — but where they land is this
# file's business, and these four variables are what makes the two agree without
# either of them guessing.
#
# Without them the server would fall back to `$HOME`, which is `/root` here
# today and is a property of the base image rather than a promise. A mount that
# lands where the server does not look is not an error: it starts, finds an
# empty cache, and says nothing about it — a silence indistinguishable from a
# machine with no dependencies downloaded.
ENV HOME=/root
ENV MAVEN_REPO_LOCAL=/root/.m2/repository
ENV GRADLE_USER_HOME=/root/.gradle
# Where a `-sources.jar` entry is unpacked so that an editor can open it, and
# where the parsed index is kept between runs. The only one of the three that
# is mounted writable, and the reason it has to be: a `file:` URI for a file
# that exists only inside the container is an answer that opens nothing.
ENV XDG_CACHE_HOME=/root/.cache

# Where the project is. The editor also passes -w, so this is the answer for
# anybody running the image by hand.
WORKDIR /workspace

# No arguments: kmp-lsp with no subcommand is the language server on standard
# input and output. Its logging goes to standard error, which is where it has
# to go — anything printed on standard output would arrive where the first
# header should be.
ENTRYPOINT ["kmp-lsp"]
