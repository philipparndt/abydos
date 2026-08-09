#!/bin/bash
# Pushes one tool image — a language server and the toolchain under it — for
# every architecture somebody runs this editor on.
#
# Usage:
#   make toolimage-publish TOOL=gopls VERSION=0.23.0
#   make toolimage-publish TOOL=gopls REPOSITORY=ghcr.io/you/gopls VERSION=0.23.0
#   make toolimage-publish DRY_RUN=1            # build both, push nothing
#
# Why buildx, when the pod publishes without it. DevPod/Makefile pushes a real
# multi-architecture image with no Docker at all, because its images are two
# static binaries: one layer of two files per architecture, a handful of blob
# uploads and an index. A language server image is not that. ToolImages/gopls is
# `FROM golang:1.26-bookworm`, so underneath the layer this repository controls
# there is a base image that exists once per architecture, and the arm64 image
# has to sit on the arm64 base. Something has to run the build once per
# architecture against the right base and write one index over the results.
# buildx is that something; writing it again here would be writing buildx again.
#
# Why one invocation with two platforms, and not two builds and a manifest.
# `docker manifest create` reads its members from the registry, so that route
# has to push each architecture under a tag of its own first — `:0.23.0-amd64`,
# `:0.23.0-arm64` — leaving two tags in the repository that nobody should ever
# pull and that no later push tidies away, and costing three pushes where one
# does. `--platform linux/amd64,linux/arm64 --push` builds both and writes a
# single index, and the only tag that appears is the one that was asked for.
#
# Why everything is checked before the first layer is built. The build is
# minutes — the amd64 half compiles gopls under emulation on an Apple machine —
# and the credentials are not wanted until the end of it. A run that discovers
# at the push that nobody is signed in has spent all of that and left nothing;
# worse, a run that discovers half way through a manifest route what it cannot
# finish leaves a repository holding something that is not what was asked for.
# So: the tool, the builder, the architectures and the login, all up front, each
# failing with the one sentence that says what to do about it.
set -euo pipefail

TOOL="${1:-}"
REPOSITORY="${2:-}"
VERSION="${3:-}"
[ -n "$TOOL" ] && [ -n "$REPOSITORY" ] && [ -n "$VERSION" ] || {
	echo "usage: publish-tool-image.sh <tool> <repository> <version>" >&2
	echo "   e.g. publish-tool-image.sh gopls pharndt/abydos-gopls 0.23.0" >&2
	exit 2
}

# The architectures Abydos runs on: Apple silicon, and the Intel machines and
# Linux CI that pull the same name.
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
# Which buildx builder to use. Unset means whichever one is current, which is
# what somebody who has made one expects.
BUILDER="${BUILDER:-}"
DRY_RUN="${DRY_RUN:-}"
TAG="$REPOSITORY:$VERSION"
CONTEXT="ToolImages/$TOOL"

# --- Is there an image to publish -------------------------------------------
#
# Named rather than looped over: each tool is its own repository, so a goal that
# published every directory in ToolImages/ from one REPOSITORY would be pushing
# six different servers to one name.
[ -f "$CONTEXT/Dockerfile" ] || {
	echo "no image for '$TOOL' — $CONTEXT/Dockerfile does not exist" >&2
	echo "   images here: $(ls ToolImages 2>/dev/null | tr '\n' ' ')" >&2
	exit 1
}

command -v docker >/dev/null || {
	echo "docker is not installed — a tool image is built by a daemon, unlike the pod's" >&2
	exit 1
}
docker buildx version >/dev/null 2>&1 || {
	echo "docker buildx is not available, and one architecture at a time is not what this publishes" >&2
	echo "   it ships with Docker 19.03 and later; on an older one, install the buildx plugin" >&2
	exit 1
}

# --- Is there a builder that can do it ---------------------------------------
#
# Not every buildx builder can. The plain `docker` driver hands the build to the
# daemon, and the daemon's image store holds one image per name — so it can
# neither build two architectures at once nor push an index, and says so only
# after the first architecture has been built. A `docker-container` builder can,
# and so can a daemon using the containerd image store.
INSPECT=$(docker buildx inspect ${BUILDER:+"$BUILDER"} 2>&1) || {
	echo "buildx cannot reach the builder ${BUILDER:-(the current one)}:" >&2
	echo "$INSPECT" | sed 's/^/   /' >&2
	echo "   list them with: docker buildx ls" >&2
	exit 1
}
BUILDER_NAME=$(printf '%s\n' "$INSPECT" | awk '/^Name:/ {print $2; exit}')
DRIVER=$(printf '%s\n' "$INSPECT" | awk '/^Driver:/ {print $2; exit}')

if [ "$DRIVER" = "docker" ]; then
	# The one exception: with the containerd image store the daemon does hold a
	# multi-architecture image, so the docker driver can push one after all.
	if ! docker info --format '{{json .DriverStatus}}' 2>/dev/null | grep -q 'io.containerd.snapshotter'; then
		echo "the buildx builder '$BUILDER_NAME' uses the docker driver, which builds one architecture at a time" >&2
		echo "   make one that does not, and this goal will use it:" >&2
		echo "     docker buildx create --name abydos --driver docker-container --use" >&2
		exit 1
	fi
fi

# What the builder says it can build, emulation included. A builder with no
# binfmt for the other architecture lists only its own, and finding that out
# here is better than finding it out as `exec format error` in the middle of a
# `go install`.
SUPPORTED=$(printf '%s\n' "$INSPECT" | sed -n 's/^Platforms:[[:space:]]*//p' | tr -d ' ' | tr '\n' ',')
[ -n "$SUPPORTED" ] || {
	echo "the builder '$BUILDER_NAME' is not running, so it cannot say which architectures it builds" >&2
	echo "   start it with: docker buildx inspect --bootstrap $BUILDER_NAME" >&2
	exit 1
}
for platform in ${PLATFORMS//,/ }; do
	case ",$SUPPORTED," in
		*",$platform,"*) ;;
		*)
			echo "the builder '$BUILDER_NAME' does not build $platform, and this publishes $PLATFORMS" >&2
			echo "   it builds: $(printf '%s' "$SUPPORTED" | sed 's/,$//')" >&2
			echo "   for the missing one, install the emulators: docker run --privileged --rm tonistiigi/binfmt --install all" >&2
			exit 1
			;;
	esac
done

# --- Is anybody signed in ----------------------------------------------------
#
# Asked of the configuration rather than of the registry, so this needs no
# network and takes nobody's password: `docker login` leaves an entry under the
# registry's key, whether the secret itself lives in the file or in a keychain
# helper, and `docker logout` takes that entry away.
#
# Skipped for a dry run, which pushes nothing and so wants nothing.
registry_key() {
	local first="${REPOSITORY%%/*}"
	case "$REPOSITORY" in
		*/*)
			case "$first" in
				*.*|*:*|localhost) printf '%s' "$first"; return ;;
			esac
			;;
	esac
	printf 'https://index.docker.io/v1/'
}
REGISTRY=$(registry_key)
# What to call it in a sentence, and what to type after `docker login`, which
# for Docker Hub are neither of them the key it is filed under.
if [ "$REGISTRY" = "https://index.docker.io/v1/" ]; then
	REGISTRY_LABEL="Docker Hub"
	LOGIN_ARG=""
else
	REGISTRY_LABEL="$REGISTRY"
	LOGIN_ARG=" $REGISTRY"
fi
if [ -z "$DRY_RUN" ]; then
	CONFIG="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
	if ! python3 - "$CONFIG" "$REGISTRY" <<-'PY'
		import json, sys
		path, registry = sys.argv[1], sys.argv[2]
		try:
		    config = json.load(open(path))
		except (OSError, ValueError):
		    sys.exit(1)
		host = registry.replace("https://", "").replace("/v1/", "")
		names = {registry, host, "docker.io"} if "docker.io" in host else {registry, host}
		auths = config.get("auths") or {}
		helpers = config.get("credHelpers") or {}
		sys.exit(0 if names & (set(auths) | set(helpers)) else 1)
	PY
	then
		echo "nothing is signed in to $REGISTRY_LABEL, and this ends in a push there" >&2
		echo "   docker login$LOGIN_ARG" >&2
		echo "   checked now rather than at the push, which is several minutes of build later" >&2
		exit 1
	fi
fi

# --- Build, and push if this is for real -------------------------------------
#
# `--pull` because a published image should not be sitting on whichever copy of
# golang:1.26-bookworm this machine happened to fetch in March. The tag moves as
# the base is patched, and the point of pushing is that somebody else runs it.
#
# A dry run exports nothing at all. `--load` is not the alternative: it takes a
# single architecture, so proving both would prove neither. `type=cacheonly`
# builds every layer of every platform and keeps the result nowhere, which is
# exactly what "would this push have worked" means.
if [ -n "$DRY_RUN" ]; then
	OUTPUT=(--output type=cacheonly)
	echo "==> Dry run: building $PLATFORMS of $CONTEXT, pushing nothing"
else
	OUTPUT=(--push)
	echo "==> Building $PLATFORMS of $CONTEXT and pushing $TAG"
fi

docker buildx build ${BUILDER:+--builder "$BUILDER"} \
	--platform "$PLATFORMS" \
	--pull \
	--tag "$TAG" \
	"${OUTPUT[@]}" \
	"$CONTEXT"

if [ -n "$DRY_RUN" ]; then
	echo "==> Both architectures build. Nothing was pushed; drop DRY_RUN to push $TAG"
	exit 0
fi

# What is now in the registry, read back from the registry — the one thing that
# says the index has both architectures under it rather than one of them with a
# second name on it.
#
# The unknown/unknown entries are skipped: buildx attaches a provenance
# attestation per platform, and each is a member of the index with no real
# platform. Worth having and not worth printing.
echo "==> Pushed $TAG"
docker buildx imagetools inspect "$TAG" --format \
	'{{range .Manifest.Manifests}}{{if ne .Platform.OS "unknown"}}    {{.Platform.OS}}/{{.Platform.Architecture}}
{{end}}{{end}}' 2>/dev/null || true
echo "    name it for a project in .abydos/tools.json: {\"$TOOL\": \"$TAG\"}"
echo "    the catalogue lists images somebody has run: add it to ToolImageCatalogue.tools"
echo "    once it has been pulled and driven, not before."
