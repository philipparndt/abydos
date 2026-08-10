#!/bin/bash
# Clones the projects the scale measurements are taken on, beside the checkout.
#
# 0428 is about a Java/RCP product of around 500 Maven bundles, and nothing in
# this repository is that shape: the performance suite's largest subject is a
# synthetic 100,000-line file in one directory. Eclipse is the corpus because it
# is the same *shape* rather than merely the same line count — Tycho, OSGi, one
# manifest per bundle, hundreds of them by construction.
#
# Beside the checkout rather than vendored, for the reason `make screenshots`
# already assumes about the examples repository: this is gigabytes of somebody
# else's source, it changes on their schedule and not ours, and a git repository
# that carries another project's history is a repository nobody can clone in an
# afternoon.
#
# Shallow, because history is not what is being measured. Not a saving worth
# arguing about either — 3.5 GB of the disk was already gone when this was
# written — but a real one: the full Platform clones are several gigabytes of
# packfile that no measurement here ever reads. What it costs is that
# `git log` on the corpus says one commit, which matters only for the git
# numbers below, and those are `git status` rather than `git log`.
#
#   Scripts/corpus.sh              # clone or update everything
#   Scripts/corpus.sh --report     # only say what is already there
#   CORPUS=~/somewhere Scripts/corpus.sh
set -euo pipefail

CORPUS="${CORPUS:-$HOME/dev/abydos-corpus}"
REPORT_ONLY=0
[ "${1:-}" = "--report" ] && REPORT_ONLY=1

# The Platform is nine repositories rather than one, which is how the Eclipse
# project itself is laid out since the aggregator was split up. Two things it
# used to include are deliberately absent: `eclipse.platform.resources` and
# `eclipse.platform.text` were folded into `eclipse.platform` and their
# repositories now hold a README and nothing else — cloning them adds two empty
# directories to the tree and one bundle to nothing.
PLATFORM_REPOS=(
	"https://github.com/eclipse-platform/eclipse.platform.git"
	"https://github.com/eclipse-platform/eclipse.platform.ui.git"
	"https://github.com/eclipse-platform/eclipse.platform.swt.git"
	"https://github.com/eclipse-jdt/eclipse.jdt.core.git"
	"https://github.com/eclipse-jdt/eclipse.jdt.ui.git"
	"https://github.com/eclipse-pde/eclipse.pde.git"
	"https://github.com/eclipse-equinox/equinox.git"
)

# Sirius rather than Papyrus for the fast inner loop. Both are RCP and Tycho and
# either would do; Sirius is one repository where Papyrus is four, and a corpus
# whose whole job is to be quick to measure should not need its own aggregator.
SIRIUS_REPO="https://github.com/eclipse-sirius/sirius-desktop.git"

clone() {
	local url="$1" into="$2"
	if [ -d "$into/.git" ]; then
		echo "  have $(basename "$into")"
		return 0
	fi
	echo "  clone $(basename "$into")"
	git clone --depth 1 --quiet "$url" "$into"
}

if [ "$REPORT_ONLY" = 0 ]; then
	mkdir -p "$CORPUS/platform"
	# Spotlight indexing gigabytes of Java in the background is exactly the kind
	# of load that makes a measurement describe the machine rather than the app,
	# and it starts the moment the first clone lands.
	touch "$CORPUS/.metadata_never_index"
	echo "==> $CORPUS"
	for url in "${PLATFORM_REPOS[@]}"; do
		name="$(basename "$url" .git)"
		clone "$url" "$CORPUS/platform/$name"
	done
	clone "$SIRIUS_REPO" "$CORPUS/sirius"
fi

# What is actually there, counted rather than assumed. A bundle is a directory
# with an OSGi manifest naming a symbolic name — not merely a `pom.xml`, because
# Tycho builds most of these pom-less and a count of poms is off by a factor of
# five in the wrong direction.
count() {
	local where="$1" label="$2"
	[ -d "$where" ] || return 0
	local bundles java lines bytes
	bundles=$(find "$where" -name MANIFEST.MF -path '*/META-INF/*' \
		-not -path '*/target/*' -not -path '*/bin/*' -print0 2>/dev/null \
		| xargs -0 grep -l 'Bundle-SymbolicName' 2>/dev/null | wc -l | tr -d ' ')
	java=$(find "$where" -name '*.java' -not -path '*/target/*' -not -path '*/bin/*' 2>/dev/null | wc -l | tr -d ' ')
	# `cat | wc -l` rather than `wc -l` over the names: forty thousand paths do
	# not fit in one `xargs` invocation, so `wc` runs several times and prints a
	# total for each batch. Taking the last of those said 108,594 lines for a
	# corpus of 3.7 million, which is the sort of number that gets written into
	# an item and believed.
	lines=$(find "$where" -name '*.java' -not -path '*/target/*' -not -path '*/bin/*' -print0 2>/dev/null \
		| xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')
	bytes=$(du -sh "$where" 2>/dev/null | awk '{print $1}')
	printf '%-14s %6s bundles  %7s .java  %10s lines  %6s on disk\n' \
		"$label" "$bundles" "$java" "${lines:-0}" "$bytes"
}

echo "==> what is there"
count "$CORPUS/platform" platform
count "$CORPUS/sirius" sirius
for repo in "$CORPUS"/platform/*/; do
	count "$repo" "  $(basename "$repo")"
done
