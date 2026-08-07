#!/bin/bash
#
# Puts the built app into /Applications without killing the one that is running.
#
# `rm -rf` followed by `cp -R` is the obvious way and it is the wrong one. A
# running application has its executable, its frameworks and its resources
# mapped out of that bundle, and macOS checks every page against the signature
# as it is faulted in. Delete the bundle and copy a different build over the
# same paths and the next page the running copy needs no longer matches what it
# was signed with — the kernel kills it, minutes later, with
# `CODESIGNING / Invalid Page` and no obvious connection to the install that
# caused it. That is what "Abydos exited twice and there is no crash report"
# turned out to be, both times, with a second session doing the installing.
#
# So: install beside it and swap by rename. A rename unlinks the old bundle
# rather than overwriting it, and unlinked files stay whole for whoever still
# has them open — the running copy keeps the build it started with, all of it,
# until it is quit.
#
# The running copy is still the old build, so it is told to restart. Refusing
# outright would be wrong: installing while it runs is exactly what somebody
# does before quitting it.
#
# Usage: Scripts/install.sh [source.app] [destination directory]

set -euo pipefail

cd "$(dirname "$0")/.."

SOURCE="${1:-build/Abydos.app}"
DESTINATION_DIR="${2:-/Applications}"
DESTINATION="$DESTINATION_DIR/Abydos.app"

[ -d "$SOURCE" ] || { echo "install: $SOURCE does not exist — run make build first" >&2; exit 1; }

# Nothing is installed over a copy that is running.
#
# The swap below leaves a running app's own bundle intact, and it still is not
# enough: the old bundle is deleted afterwards, and an application that has not
# yet loaded every nib, framework and resource it is going to load needs the
# files it started with to still be there. There is no way to know when it is
# finished with them, and a program that quietly loses half its bundle fails
# later and somewhere else — which is what "it crashed during make install and
# there is no crash report" looks like.
#
# Quitting first is needed to get the new build in any case, so this asks for it
# rather than working around it. FORCE=1 for somebody who means it.
running() {
	pgrep -f "^$DESTINATION/Contents/MacOS/Abydos" >/dev/null 2>&1
}

if running && [ "${FORCE:-0}" != "1" ]; then
	echo "install: Abydos is running from $DESTINATION" >&2
	echo "  Quit it first — the running copy keeps the old build until it is quit anyway." >&2
	echo "  Or: make install FORCE=1" >&2
	exit 1
fi

# Staged beside the destination rather than inside its directory, and on the
# same filesystem so the swap is a rename.
#
# Not inside /Applications: a second bundle appearing there with the same
# identifier is a second registration, however briefly, and LaunchServices is
# entitled to decide what that means for the copy already running.
STAGING="${TMPDIR:-/tmp}/abydos-install.$$"
RETIRED="${TMPDIR:-/tmp}/abydos-replaced.$$"

cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

rm -rf "$STAGING"
# `ditto` rather than `cp -R`: it carries the extended attributes a signature
# lives in, which `cp` on some systems does not, and a bundle that arrives
# without them is a bundle Gatekeeper refuses.
ditto "$SOURCE" "$STAGING"

# The swap. A rename unlinks the old bundle rather than overwriting it, so even
# with FORCE a running copy keeps every file it started with — and the old
# bundle is only deleted when nothing is running from it.
if [ -e "$DESTINATION" ]; then
	mv "$DESTINATION" "$RETIRED"
fi
mv "$STAGING" "$DESTINATION"

if running; then
	echo "==> Installed $DESTINATION"
	echo "    a copy is still running the previous build — quit and reopen it to get this one"
	echo "    the build it is running is kept at $RETIRED until then"
else
	rm -rf "$RETIRED"
	echo "==> Installed $DESTINATION"
fi
