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

[ -d "$SOURCE" ] || { echo "install: $SOURCE does not exist — run make release first" >&2; exit 1; }

# Only a notarized bundle goes into /Applications.
#
# `make build` signs with the Developer ID but does not notarize, and a bundle
# written by a tracked process carries provenance, so Gatekeeper treats it as a
# download: on first launch it finds no ticket and refuses it with "Apple could
# not verify". Worse, the refusal is remembered against the bundle's folder, so
# a notarized build copied into the same folder later is refused too. That is
# what "the release is fine but it still will not start" turned out to be.
#
# The ticket is stapled by Scripts/release.sh; `stapler validate` is the check
# that Gatekeeper itself would pass offline. ALLOW_UNNOTARIZED=1 installs anyway,
# for the case where the destination is not /Applications or the refusal is
# understood.
if ! xcrun stapler validate "$SOURCE" >/dev/null 2>&1; then
	if [ "${ALLOW_UNNOTARIZED:-0}" = "1" ]; then
		echo "install: $SOURCE is not notarized — installing anyway (ALLOW_UNNOTARIZED=1); Gatekeeper will refuse it on first launch" >&2
	else
		echo "install: $SOURCE is not notarized — Gatekeeper would refuse it on first launch" >&2
		echo "  run make release first, or ALLOW_UNNOTARIZED=1 make install to install it anyway" >&2
		exit 1
	fi
fi

# A copy that is running is left able to keep running.
#
# The swap below is a rename, so the old bundle is unlinked rather than
# overwritten and whatever is running keeps every file it started with. That is
# the whole of what is needed. This used to refuse outright unless FORCE=1 was
# set, on the theory that installing was what kept killing the app — it was not.
# The app was dying of SIGPIPE, and refusing to install was a toll charged for a
# crossing that was never the problem.
#
# What is still true, and worth saying once: the running copy is running the old
# build until it is quit.
running() {
	pgrep -f "^$DESTINATION/Contents/MacOS/Abydos" >/dev/null 2>&1
}

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
