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

# Staged in the destination's own directory, because a rename is only atomic
# within one filesystem: /Applications and build/ need not be on the same one.
STAGING="$DESTINATION_DIR/.Abydos.app.incoming.$$"
RETIRED="$DESTINATION_DIR/.Abydos.app.replaced.$$"

cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

rm -rf "$STAGING"
# `ditto` rather than `cp -R`: it carries the extended attributes a signature
# lives in, which `cp` on some systems does not, and a bundle that arrives
# without them is a bundle Gatekeeper refuses.
ditto "$SOURCE" "$STAGING"

if [ -e "$DESTINATION" ]; then
	mv "$DESTINATION" "$RETIRED"
fi
mv "$STAGING" "$DESTINATION"
rm -rf "$RETIRED"

echo "==> Installed $DESTINATION"

# Anybody still running the old one is running something that no longer exists
# on disk. It will not be killed for it, but it will not have this build either.
if pgrep -f "^$DESTINATION/Contents/MacOS/Abydos" >/dev/null 2>&1; then
	echo "    a copy is still running the previous build — quit and reopen it to get this one"
fi
