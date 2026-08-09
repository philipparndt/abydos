#!/bin/bash
#
# Vendors draw.io, which is how this app draws and edits `.drawio` files.
#
# draw.io publishes exactly one artefact — `draw.war`, the webapp — and no npm
# package (`drawio` on npm is an unrelated charting tool by somebody else). The
# `.war` is a zip; this takes the handful of files out of it that a viewer and
# an editor need, and leaves 120 MB of the rest behind.
#
# What is taken, and why each one:
#
#   js/viewer-static.min.js   the off-screen renderer, for Export ▸ PNG / SVG
#   js/app.min.js             the editor itself
#   js/shapes-14-6-5.min.js   every JavaScript-implemented shape, in one file
#   js/stencils.min.js        every stencil, deflated, served from memory —
#                             see the note below, it is the whole reason this
#                             works with no network at all
#   styles/                   the stylesheets a graph decodes at load
#   mxgraph/{css,images}      mxGraph's own furniture
#   resources/dia.txt         the English strings; the other forty languages
#                             are 5.6 MB and nobody has asked for one
#   images/                   the editor's icons — *without* `sidebar-*.png`,
#                             which are 6.1 MB of preview sprites for the More
#                             Shapes dialogue and nothing else
#
# What is deliberately **not** taken:
#
#   templates/    CC-BY-4.0 rather than Apache-2.0, and it is the New-diagram
#                 gallery, which an editor opening an existing file never shows
#   img/lib/      5.9 MB of clipart that `shape=image` cells reference by path.
#                 A diagram using one draws a gap where a picture goes, so
#                 `Drawio.missingClipart` looks for the reference and says so
#                 rather than the app carrying the megabytes. See 0426.
#   stencils/     42.8 MB of XML, all of which is inside stencils.min.js
#   shapes/       2.3 MB of the same, likewise inside shapes-14-6-5.min.js
#   extensions.min.js, plugins/, math4/, images/sidebar-*.png
#
# Re-run to update: change VERSION below, run from the repo root, then say the
# new version in THIRD-PARTY-NOTICES.md, which is the only other place it is
# written down.

set -euo pipefail

VERSION="${1:-31.1.8}"

cd "$(dirname "$0")/.."
DEST="Sources/AbydosKit/Preview/drawio"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> drawio $VERSION"
curl -fsSL -o "$WORK/draw.war" \
	"https://github.com/jgraph/drawio/releases/download/v${VERSION}/draw.war"
unzip -q -o "$WORK/draw.war" -d "$WORK/war" \
	'js/viewer-static.min.js' 'js/app.min.js' 'js/shapes-14-6-5.min.js' \
	'js/stencils.min.js' 'styles/*' 'mxgraph/css/*' 'mxgraph/images/*' \
	'resources/dia.txt' 'images/*' 'stencils/LICENSE' 'img/LICENSE'
# The Apache-2.0 text itself is in the repository rather than in the webapp,
# which ships only the two riders below.
curl -fsSL -o "$WORK/LICENSE" \
	"https://raw.githubusercontent.com/jgraph/drawio/v${VERSION}/LICENSE"

rm -rf "$DEST"
mkdir -p "$DEST/js" "$DEST/styles" "$DEST/mxgraph" "$DEST/resources"

cp "$WORK/war/js/viewer-static.min.js" "$WORK/war/js/app.min.js" \
	"$WORK/war/js/shapes-14-6-5.min.js" "$WORK/war/js/stencils.min.js" "$DEST/js/"
# The fonts folder inside styles/ is web fonts fetched by URL; nothing here
# fetches, so it is left behind.
cp "$WORK"/war/styles/*.xml "$WORK"/war/styles/*.css "$WORK"/war/styles/*.png "$DEST/styles/"
cp -R "$WORK/war/mxgraph/css" "$WORK/war/mxgraph/images" "$DEST/mxgraph/"
cp "$WORK/war/resources/dia.txt" "$DEST/resources/"
mkdir -p "$DEST/images"
# Everything but the More Shapes sprites, which are 6.1 MB of the 6.4.
find "$WORK/war/images" -maxdepth 1 -type f ! -name 'sidebar-*' -exec cp {} "$DEST/images/" \;

# Three licences, because three parts of this tree are under different terms.
cp "$WORK/LICENSE" "$DEST/LICENSE"
cp "$WORK/war/stencils/LICENSE" "$DEST/LICENSE-stencils"
cp "$WORK/war/img/LICENSE" "$DEST/LICENSE-img"
printf '%s\n' "$VERSION" > "$DEST/VERSION"

# The two checks that matter, and both are things a new release could quietly
# change into a blank pane.
#
# `stencils.min.js` is not a list of files: it replaces
# `mxStencilRegistry.loadStencil` with one that serves 42.8 MB of stencil XML
# out of 7.6 MB held in memory. That override is the only reason no stencil is
# ever fetched, and a build without it would draw diagrams short of their icons
# and say nothing at all.
if ! grep -q 'mxStencilRegistry.loadStencil = function' "$DEST/js/stencils.min.js"; then
	echo "error: stencils.min.js no longer overrides loadStencil — shapes would be fetched" >&2
	exit 1
fi
# And every asset path this points at somewhere unreachable is a
# `window.X = window.X || …` default, which is what lets the page declare its
# own before the bundle loads.
for global in STENCIL_PATH SHAPES_PATH STYLE_PATH GRAPH_IMAGE_PATH mxBasePath; do
	if ! grep -q "window.$global=window.$global||" "$DEST/js/viewer-static.min.js"; then
		echo "error: viewer-static.min.js no longer defaults $global — the page cannot set it" >&2
		exit 1
	fi
done

echo "    $DEST — $(du -sh "$DEST" | cut -f1), Apache-2.0"
