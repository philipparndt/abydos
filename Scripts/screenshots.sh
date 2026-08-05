#!/bin/bash
# Photographs the app for the documentation, using the examples repository.
#
# The examples exist to be developed *with*, which makes them the honest thing
# to photograph: every shot below is the app doing the thing the page claims,
# on a project anybody can clone and try. Nothing is staged and nothing is
# drawn by hand.
#
# Reproducible on purpose. The window is given a size, the panel is given a
# height, and each project is copied to a temporary directory first — because
# the window frame, the split position and which files were last open are all
# remembered per machine, and a screenshot that depends on them is a screenshot
# that looks different for everybody who takes it.
#
#   make screenshots                      # all of them
#   make screenshots SHOT=debugger        # one
#   make screenshots EXAMPLES=~/dev/x     # from somewhere else
set -euo pipefail

cd "$(dirname "$0")/.."

EXAMPLES="${EXAMPLES:-../ideai-examples}"
OUT="${OUT:-docs/images}"
SIZE="${SIZE:-1600x1000}"
ONLY="${SHOT:-}"
APP="build/ideai.app/Contents/MacOS/ideai"

test -d "$EXAMPLES" || {
	echo "no examples at $EXAMPLES — clone philipparndt/ideai-examples or set EXAMPLES="
	exit 1
}
test -x "$APP" || { echo "no $APP — run make build CONFIG=debug first"; exit 1; }

EXAMPLES="$(cd "$EXAMPLES" && pwd)"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A copy, not the original: opening a project writes a session file into it,
# and a subdirectory of a git repository resolves to the repository root — so
# `--open examples/go-service` opens the whole examples repo with whatever was
# last open in it.
prepare() {
	local example="$1" name="$2"
	rm -rf "${WORK:?}/$name"
	cp -R "$EXAMPLES/$example" "$WORK/$name"
	rm -rf "$WORK/$name/.ideai/session.json" "$WORK/$name/build" "$WORK/$name/target"
	echo "$WORK/$name"
}

# One capture. Everything after the name is handed to the app.
shoot() {
	local name="$1"; shift
	if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then return 0; fi

	printf '  %-12s ' "$name"
	"$APP" --window-size "$SIZE" --screenshot "$OUT/$name.png" "$@" >/dev/null 2>&1 || true
	if [ -f "$OUT/$name.png" ]; then
		printf '%s\n' "$(du -h "$OUT/$name.png" | cut -f1)"
	else
		printf 'FAILED\n'
		return 1
	fi
}

echo "==> Photographing into $OUT ($SIZE)"

# The editor and the navigator, on a project small enough to take in.
GO="$(prepare go-service go-service)"
shoot editor --open "$GO" --file "$GO/main.go" --expand --panel-height 0 --delay 4

# The claim that matters: stopped on a breakpoint. Started with the terminal
# filling the window, because that is both the state people work in and the one
# the debugger has to recover from.
#
# No `--file`: stopping opens the file itself, and opening it first leaves two
# tabs for the one file — the debugger names it by the path Delve reports,
# which is the resolved one.
shoot debugger --open "$GO" \
	--maximize-terminal --breakpoint 25 --debug-line 18 --delay 40

# A terminal that is a terminal: tmux's own windows as the panel's tabs.
shoot terminal --open "$GO" --terminal --panel-height 420 --delay 6

# Java, because "a language is supported" is a claim about a build file as much
# as about source: the outline over a POM comes from Maven's own structure.
JAVA="$(prepare java/maven-service maven-service)"
shoot java --open "$JAVA" --file "$JAVA/src/main/java/com/example/api/Server.java" \
	--expand --panel-height 0 --delay 5

# No git shot. These are copies, and a copy has no `.git` — the changes pane
# would be photographed empty, which says the opposite of what it is for.
# Photographing the examples repository itself instead would mean whatever
# somebody happened to have uncommitted that day.

echo "==> Done. $(ls "$OUT" | wc -l | tr -d ' ') images in $OUT"
