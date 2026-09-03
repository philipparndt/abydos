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
# What the machine happens to be doing at the time is kept out too: a capture
# run does not take the Claude hook's announcements, so somebody's agent
# finishing in the eight seconds before the shutter no longer stacks a toast
# over the bottom right corner (0451). A shot that wants a toast in it still
# asks for one, with `--toast`.
#
# The same for the `Claude Sessions` root, which would otherwise put whoever is
# working on the machine into a picture of the tree: a capture reads no
# transcript times and never hears the hook, so a shot that wants a session
# running in it asks with `--claude-running <id>`, or `<id>@<seconds>` to have
# it start while the window is open, or `<id>:<status>` to say what it is doing
# — and more than once, for a pill with a session in each state.
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
APP="build/Abydos.app/Contents/MacOS/Abydos"

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
	rm -rf "$WORK/$name/.abydos/session.json" "$WORK/$name/.ideai/session.json" "$WORK/$name/build" "$WORK/$name/target"
	echo "$WORK/$name"
}

# One capture. Everything after the name is handed to the app.
shoot() {
	local name="$1"; shift
	if [ -n "$ONLY" ] && [ "$ONLY" != "$name" ]; then return 0; fi

	printf '  %-12s ' "$name"
	# In the app's own palette, so the pictures do not depend on whichever
	# theme the machine taking them happens to be set to.
	"$APP" --window-size "$SIZE" --theme abydos --screenshot "$OUT/$name.png" "$@" >/dev/null 2>&1 || true
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

# A terminal that is a terminal: tmux's own windows as the panel's tabs, with
# something in them. The first version photographed one empty window, which
# proves the tabs exist and nothing about what they are for — so a second
# window is opened from inside the terminal, the way anybody would, and a real
# build runs in it.
#
# Typed at the shell rather than with `--type`, which types wherever the
# keyboard is — and that is the editor, so the first attempt photographed two
# tmux commands inserted into main.go.
#
# The session is named after the project and outlives the app, so a second run
# found the window from the first and made another beside it — three tabs
# saying "build". Killed first, so the picture is of one run.
tmux kill-session -t "$(basename "$GO")" 2>/dev/null || true
shoot terminal --open "$GO" --file "$GO/main.go" --terminal --panel-height 420 \
	--run "tmux new-window -n build -c '$GO'" \
	--send-bytes 'go build -v -o /dev/null ./... && go vet ./... && echo "  build ok"\r' \
	--delay 16

# The pill on the terminal's title bar counting every Claude session on the
# machine, and the list under it. A capture hears no hook, so the sessions are
# put in the register by hand, one in each state. The list is a popover, which
# is a window of its own and so is written beside the picture as
# `sessions-child0.png` rather than into it.
shoot sessions --open "$GO" --file "$GO/main.go" --terminal --panel-height 420 \
	--claude-running 11111111-1111-4111-8111-111111111111:working \
	--claude-running 22222222-2222-4222-8222-222222222222:needs \
	--claude-running 33333333-3333-4333-8333-333333333333:done \
	--running-sessions-menu 4 --delay 7

# Java, because "a language is supported" is a claim about a build file as much
# as about source: the outline over a POM comes from Maven's own structure.
JAVA="$(prepare java/maven-service maven-service)"
shoot java --open "$JAVA" --file "$JAVA/src/main/java/com/example/api/Server.java" \
	--expand --panel-height 0 --delay 5

# A diagram, which is the one part of this app a paragraph is worse at than a
# picture: the source on the left, the drawing on the right, and the drawing
# redrawn on every pause in the typing.
#
# Mermaid rather than PlantUML on purpose, and it is the honest choice rather
# than the flattering one — a `.puml` needs a container runtime and an image
# pulled, so a machine taking these pictures with neither would photograph an
# install hint. Mermaid needs nothing at all (0425), so this shot is the same
# on every machine.
#
# `--file` is enough to open the split: a `.mmd` is a file whose rendered form
# is the point of it, so it opens as source and drawing rather than as text.
# The delay is longer than the editor's because the first render also loads the
# bundle into the web view.
#
# `document.mmd` of the six, because it is the one whose whole picture fits the
# pane at a size somebody can read — the flowchart in `render.mmd` is taller
# than the window and photographs as a diagram with its bottom cut off, and the
# sequence diagram fits only by shrinking to 54%. Fitting is the pane doing its
# job either way, but a picture of it should be of the case that reads.
MMD="$(prepare mermaid mermaid)"
shoot diagram --open "$MMD" --file "$MMD/document.mmd" --panel-height 0 --delay 8

# What a breakpoint can be told to do. Drawn by hand, so it is photographed
# rather than described — and the values come from the session file, which is
# also how anybody's would.
BP="$(prepare go-service bp-options)"
mkdir -p "$BP/.abydos"
cat > "$BP/.abydos/session.json" <<'SESSION'
{
  "files": [{ "path": "REPLACED/main.go", "line": 25 }],
  "active": "REPLACED/main.go",
  "breakpoints": [{
    "path": "REPLACED/main.go",
    "line": 25,
    "condition": "stage == \"local\" && len(os.Args) > 1",
    "hits": "> 5",
    "log": "stage is {stage} after {time.Since(started)}"
  }]
}
SESSION
# The path is only knowable now: these are copies in a temporary directory.
REAL="$(cd "$BP" && pwd -P)"
# Rewritten with python rather than sed: the path holds slashes and the shell
# quoting around `sed -i ''` on macOS is one mistake away from an empty
# expression, which is what happened.
python3 - "$BP/.abydos/session.json" "$REAL" <<'PYTHON'
import sys
path, real = sys.argv[1], sys.argv[2]
text = open(path).read().replace("REPLACED", real)
open(path, "w").write(text)
PYTHON
shoot breakpoint --open "$BP" --panel-height 200 --bp-edit 25 --delay 8
# The sheet is a window of its own, so it lands beside the capture.
if [ -f "$OUT/breakpoint-sheet.png" ]; then
	mv "$OUT/breakpoint-sheet.png" "$OUT/breakpoint.png"
fi

# No git shot. These are copies, and a copy has no `.git` — the changes pane
# would be photographed empty, which says the opposite of what it is for.
# Photographing the examples repository itself instead would mean whatever
# somebody happened to have uncommitted that day.

echo "==> Done. $(ls "$OUT" | wc -l | tr -d ' ') images in $OUT"
