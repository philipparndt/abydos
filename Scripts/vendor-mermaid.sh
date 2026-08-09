#!/bin/bash
#
# Vendors mermaid's browser bundle, which is how this app draws Mermaid.
#
# Mermaid is JavaScript and every command-line form of it carries a headless
# Chromium: `minlag/mermaid-cli` measured 2.16 GB on disk against this one
# file's 3.6 MB, and it has no server mode to keep warm the way PlantUML's
# image does. So the bundle is loaded into a WKWebView instead — see backlog
# 0425 for the numbers.
#
# The single UMD file is deliberately the one taken rather than the ESM build:
# it sets `globalThis.mermaid` and needs no module loader, no import map and no
# second request, which is what makes it work from a `loadHTMLString` page with
# no origin at all.
#
# Re-run to update: change VERSION below and run from the repo root. Then say
# the new version in THIRD-PARTY-NOTICES.md, which is the only other place it
# is written down.

set -euo pipefail

VERSION="${1:-11.16.1}"

cd "$(dirname "$0")/.."
DEST="Sources/AbydosKit/Preview/mermaid"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> mermaid $VERSION"
curl -fsSL -o "$WORK/mermaid.tgz" \
	"https://registry.npmjs.org/mermaid/-/mermaid-${VERSION}.tgz"
tar xzf "$WORK/mermaid.tgz" -C "$WORK" package/dist/mermaid.min.js package/LICENSE

mkdir -p "$DEST"
cp "$WORK/package/dist/mermaid.min.js" "$DEST/mermaid.min.js"
cp "$WORK/package/LICENSE" "$DEST/LICENSE"
printf '%s\n' "$VERSION" > "$DEST/VERSION"

# The check that matters: the bundle has to end by publishing the global the
# page looks for. A build that changed that would load without complaint and
# then draw nothing.
if ! tail -c 200 "$DEST/mermaid.min.js" | grep -q 'globalThis\["mermaid"\]'; then
	echo "error: this bundle does not set globalThis.mermaid — the page would find nothing" >&2
	exit 1
fi

echo "    $DEST/mermaid.min.js ($(wc -c < "$DEST/mermaid.min.js" | tr -d ' ') bytes), MIT"
