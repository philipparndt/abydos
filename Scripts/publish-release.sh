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
DMG="build/ideai-$VERSION.dmg"

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

git tag -a "$TAG" -m "ideai $VERSION"

# --- Build, sign, notarise --------------------------------------------------
#
# After the tag, so the build number and commit stamped into the bundle are
# the ones the tag names.
make --no-print-directory build CONFIG=release
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

NOTES=$(mktemp)
{
	echo "### Install"
	echo
	echo "Download \`$(basename "$DMG")\`, open it and drag ideai to Applications."
	echo "The build is signed with a Developer ID and notarised, so Gatekeeper opens it"
	echo "without a detour through System Settings."
	echo
	echo "    shasum -a 256 -c $(basename "$DMG").sha256"
	echo
	echo "Requires macOS 14 or newer."
} > "$NOTES"

gh release create "$TAG" \
	"$DMG" "$DMG.sha256" \
	--title "ideai $VERSION" \
	--notes-file "$NOTES" \
	--generate-notes
rm -f "$NOTES"

echo "==> Published $TAG"
gh release view "$TAG" --json url --jq .url
