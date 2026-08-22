#!/bin/bash
# Cuts a release: stamps the version, tags it, builds and notarises from that
# tag, and uploads the signed disk image to GitHub.
#
# One command, because a release done by hand is a release where the tag and
# the thing people download disagree about which build they are. Everything
# here is in one order for one reason: the version is written first so the app
# reports it, the tag is made before the build so the binary is stamped with
# the commit it claims, and the upload happens last so a failed notarisation
# never leaves a release with nothing in it.
#
# The Homebrew tap is the last step, in Scripts/update-tap.sh — after the
# release, because the cask names a download that has to be there first.
#
# Usage:
#   make release-publish VERSION=0.2.0
#
# Needs: a Developer ID certificate, a stored `notarytool` keychain profile
# (see Scripts/release.sh), and `gh` logged in.
set -euo pipefail

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: publish-release.sh <version>   e.g. 0.2.0"; exit 2; }
# `v` belongs on the tag and nowhere else: CFBundleShortVersionString is a
# number, and Sparkle-less update checks compare it as one.
VERSION="${VERSION#v}"
TAG="v$VERSION"
PLIST="Resources/Info.plist"
DMG="build/Abydos-$VERSION.dmg"

command -v gh >/dev/null || { echo "gh is not installed — brew install gh"; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "gh is not logged in — gh auth login"; exit 1; }
security find-identity -v -p codesigning | grep -q "Developer ID Application" \
	|| { echo "no Developer ID Application certificate in the keychain"; exit 1; }

# The chart the app ships is a copy of the one in DevPod/, and the build syncs
# it. Synced *before* the clean check rather than during the build, so a chart
# that has drifted is a change to commit rather than a working tree left dirty
# by the release itself.
make --no-print-directory devpod-chart >/dev/null

# A release is built from what is committed. A dirty tree means the tag would
# point at something nobody else can reproduce.
if ! git diff --quiet || ! git diff --cached --quiet; then
	echo "the working tree has changes — commit or stash them first"
	exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
	echo "$TAG already exists"
	exit 1
fi

BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "==> Releasing $TAG from $BRANCH"

# --- The version the app reports -------------------------------------------
CURRENT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
if [ "$CURRENT" != "$VERSION" ]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
	git add "$PLIST"
	git commit -q -m "Release $VERSION"
	echo "    version $CURRENT → $VERSION"
fi

git tag -a "$TAG" -m "Abydos $VERSION"

# --- Build, sign, notarise --------------------------------------------------
#
# After the tag, so the build number and commit stamped into the bundle are
# the ones the tag names.
# `PIN_UUID=0` is not optional here, and leaving it out is why this script used to
# refuse itself at the next step. The pin exists so a *local* build keeps the macOS
# Local Network grant, which is filed against one executable UUID; a release
# carrying that borrowed UUID is a release whose crash reports cannot say which
# build they came from, and `release.sh` checks for exactly that. `make release`
# passed it and this path did not, so the one command that is meant to do the whole
# thing was the one that stopped halfway — after tagging.
make --no-print-directory build CONFIG=release PIN_UUID=0
Scripts/release.sh

test -f "$DMG" || { echo "expected $DMG and it is not there"; exit 1; }

# A checksum beside the image: the signature says Apple trusts it, and this
# says it is the same file that left this machine.
shasum -a 256 "$DMG" | sed "s#build/##" > "$DMG.sha256"

# --- Publish ----------------------------------------------------------------
#
# The tag is pushed before the release is created: `gh release create` on a tag
# GitHub has never seen makes one at whatever main happens to be, which is not
# necessarily what was built.
git push origin "$BRANCH"
git push origin "$TAG"

# What changed, written by hand, with the install lines appended.
#
# `docs/release-notes-<version>.md` is the release's own notes: grouped by what
# somebody would notice rather than by what changed, and carrying the
# measurements that decided things. Written before the tag, reviewed like
# anything else, and versioned — which is the point of it being a file rather
# than something typed into a box at the end.
#
# A version with no such file stops here rather than publishing a release whose
# only description is a list of commit subjects. Writing them is part of cutting
# a release, and a download nobody can read the changes for is worse than one
# that is a day later.
HAND_NOTES="docs/release-notes-$VERSION.md"
if [ ! -f "$HAND_NOTES" ]; then
	echo "no release notes at $HAND_NOTES" >&2
	echo "write them first — they are the release, not a formality" >&2
	exit 1
fi

NOTES=$(mktemp)
{
	cat "$HAND_NOTES"
	echo
	echo "### Install"
	echo
	echo "    brew tap philipparndt/abydos"
	echo "    brew trust philipparndt/abydos"
	echo "    brew install --cask abydos"
	echo
	echo "Homebrew 6 refuses a cask from a tap outside its own repositories until"
	echo "\`brew trust\` says otherwise; that is what the middle line is."
	echo
	echo "Or download \`$(basename "$DMG")\`, open it and drag Abydos to Applications."
	echo "The build is signed with a Developer ID and notarised, so Gatekeeper opens it"
	echo "without a detour through System Settings."
	echo
	echo "    shasum -a 256 -c $(basename "$DMG").sha256"
	echo
	echo "Requires macOS 14 or newer."
} > "$NOTES"

# No `--generate-notes`: it appends GitHub's own list of commit subjects, which
# next to notes somebody wrote reads as the same release described twice, once
# badly. The tag's commits are a click away in the compare view either way.
gh release create "$TAG" \
	"$DMG" "$DMG.sha256" \
	--title "Abydos $VERSION" \
	--notes-file "$NOTES"
rm -f "$NOTES"

# --- And the tap ------------------------------------------------------------
#
# After the release exists, never before it: the cask carries the URL of the
# image that was just uploaded, and a tap pointing at a download GitHub does not
# have yet is a `brew install` that fails for whoever is quickest.
Scripts/update-tap.sh "$VERSION"

echo "==> Published $TAG"
gh release view "$TAG" --json url --jq .url
